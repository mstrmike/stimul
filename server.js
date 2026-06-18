require('dotenv').config();
const express = require('express');
const path = require('path');
const XLSX = require('xlsx');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const db = require('./db');

const app = express();
const PORT = Number(process.env.PORT || 3000);
const PERIOD_NAME = '2024–2026';
const sessions = new Map();

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

function parseCookies(req) {
  const header = req.headers.cookie || '';
  return header.split(';').reduce((acc, item) => {
    const [k, ...rest] = item.trim().split('=');
    if (!k) return acc;
    acc[k] = decodeURIComponent(rest.join('='));
    return acc;
  }, {});
}

function getSession(req) {
  const sid = parseCookies(req).sid;
  return sid && sessions.has(sid) ? sessions.get(sid) : null;
}

function requireAuth(req, res, next) {
  const session = getSession(req);
  if (!session) return res.status(401).json({ ok: false, error: 'Требуется вход в систему' });
  req.session = session;
  next();
}

function requireAdmin(req, res, next) {
  const session = getSession(req);
  if (!session) return res.status(401).json({ ok: false, error: 'Требуется вход в систему' });
  if (session.role !== 'admin') return res.status(403).json({ ok: false, error: 'Недостаточно прав' });
  req.session = session;
  next();
}

async function ensureAuditTable() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS audit_log (
      id BIGSERIAL PRIMARY KEY,
      actor_name TEXT NOT NULL,
      actor_role TEXT NOT NULL,
      action_type TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      entity_id TEXT,
      details JSONB,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
}

async function ensureUsersTable() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS app_users (
      id BIGSERIAL PRIMARY KEY,
      username TEXT NOT NULL UNIQUE,
      full_name TEXT NOT NULL,
      password_hash TEXT NOT NULL,
      role TEXT NOT NULL CHECK (role IN ('admin','editor','viewer')),
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      last_login_at TIMESTAMPTZ
    )
  `);
  await db.query(`CREATE INDEX IF NOT EXISTS idx_app_users_role ON app_users(role)`);
}

async function seedInitialAdmin() {
  await ensureUsersTable();
  const username = process.env.INITIAL_ADMIN_USERNAME || 'admin';
  const password = process.env.INITIAL_ADMIN_PASSWORD || 'admin123';
  const fullName = process.env.INITIAL_ADMIN_FULL_NAME || 'Главный администратор';
  const existing = await db.query(`SELECT id FROM app_users WHERE username = $1 LIMIT 1`, [username]);
  if (existing.rows.length) return;
  const hash = await bcrypt.hash(password, 10);
  await db.query(`INSERT INTO app_users (username, full_name, password_hash, role, is_active) VALUES ($1, $2, $3, 'admin', TRUE)`, [username, fullName, hash]);
}

async function writeAudit(actor, actionType, entityType, entityId, details) {
  await ensureAuditTable();
  await db.query(`INSERT INTO audit_log (actor_name, actor_role, action_type, entity_type, entity_id, details) VALUES ($1, $2, $3, $4, $5, $6)`, [actor?.username || 'system', actor?.role || 'system', actionType, entityType, entityId ? String(entityId) : null, details || {}]);
}

function sendWorkbook(res, workbook, filename) {
  const buffer = XLSX.write(workbook, { bookType: 'xlsx', type: 'buffer' });
  res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
  res.send(buffer);
}

async function payloadFromReq(req) {
  const { studentId, criterionId, gradeAtResult, gradeTrack, dynamicBonus, rawResultValue, resultDate, comment } = req.body || {};
  return { studentId, criterionId, gradeAtResult, gradeTrack, dynamicBonus, rawResultValue, resultDate, comment };
}

app.post('/api/login', async (req, res) => {
  try {
    await seedInitialAdmin();
    const { username, password } = req.body || {};
    const userRes = await db.query(`SELECT id, username, full_name, password_hash, role, is_active FROM app_users WHERE username = $1 LIMIT 1`, [username]);
    if (!userRes.rows.length) return res.status(401).json({ ok: false, error: 'Неверный логин или пароль' });
    const user = userRes.rows[0];
    if (!user.is_active) return res.status(403).json({ ok: false, error: 'Учётная запись отключена' });
    const ok = await bcrypt.compare(password || '', user.password_hash);
    if (!ok) return res.status(401).json({ ok: false, error: 'Неверный логин или пароль' });
    await db.query(`UPDATE app_users SET last_login_at = NOW(), updated_at = NOW() WHERE id = $1`, [user.id]);
    const sid = crypto.randomBytes(24).toString('hex');
    const session = { userId: user.id, username: user.username, fullName: user.full_name, role: user.role, createdAt: new Date().toISOString() };
    sessions.set(sid, session);
    res.setHeader('Set-Cookie', `sid=${sid}; Path=/; HttpOnly; SameSite=Lax`);
    await writeAudit(session, 'login', 'app_user', user.id, { username: user.username });
    res.json({ ok: true, user: session });
  } catch (error) {
    res.status(500).json({ ok: false, error: error.message });
  }
});

app.post('/api/logout', requireAuth, async (req, res) => {
  const cookies = parseCookies(req);
  sessions.delete(cookies.sid);
  res.setHeader('Set-Cookie', 'sid=; Path=/; HttpOnly; Max-Age=0; SameSite=Lax');
  await writeAudit(req.session, 'logout', 'session', cookies.sid, {});
  res.json({ ok: true });
});

app.get('/api/me', requireAuth, async (req, res) => res.json({ ok: true, user: req.session }));

app.get('/api/users', requireAdmin, async (req, res) => {
  try {
    await ensureUsersTable();
    const result = await db.query(`SELECT id, username, full_name, role, is_active, created_at, updated_at, last_login_at FROM app_users ORDER BY id DESC`);
    res.json({ ok: true, rows: result.rows });
  } catch (error) { res.status(500).json({ ok: false, error: error.message }); }
});

app.post('/api/users', requireAdmin, async (req, res) => {
  try {
    await ensureUsersTable();
    const { username, fullName, password, role, isActive } = req.body || {};
    if (!username || !fullName || !password || !role) return res.status(400).json({ ok: false, error: 'Нужны username, fullName, password, role' });
    const hash = await bcrypt.hash(password, 10);
    const insertRes = await db.query(`INSERT INTO app_users (username, full_name, password_hash, role, is_active) VALUES ($1, $2, $3, $4, $5) RETURNING id, username, full_name, role, is_active`, [username, fullName, hash, role, isActive !== false]);
    await writeAudit(req.session, 'create', 'app_user', insertRes.rows[0].id, { username, role });
    res.status(201).json({ ok: true, user: insertRes.rows[0] });
  } catch (error) { res.status(500).json({ ok: false, error: error.message }); }
});

app.put('/api/users/:id', requireAdmin, async (req, res) => {
  try {
    await ensureUsersTable();
    const userId = Number(req.params.id);
    const { fullName, role, isActive, password } = req.body || {};
    if (!userId) return res.status(400).json({ ok: false, error: 'Некорректный ID' });
    const existing = await db.query(`SELECT id FROM app_users WHERE id = $1 LIMIT 1`, [userId]);
    if (!existing.rows.length) return res.status(404).json({ ok: false, error: 'Пользователь не найден' });
    if (password) {
      const hash = await bcrypt.hash(password, 10);
      await db.query(`UPDATE app_users SET full_name = COALESCE($2, full_name), role = COALESCE($3, role), is_active = COALESCE($4, is_active), password_hash = $5, updated_at = NOW() WHERE id = $1`, [userId, fullName || null, role || null, typeof isActive === 'boolean' ? isActive : null, hash]);
    } else {
      await db.query(`UPDATE app_users SET full_name = COALESCE($2, full_name), role = COALESCE($3, role), is_active = COALESCE($4, is_active), updated_at = NOW() WHERE id = $1`, [userId, fullName || null, role || null, typeof isActive === 'boolean' ? isActive : null]);
    }
    const result = await db.query(`SELECT id, username, full_name, role, is_active, created_at, updated_at, last_login_at FROM app_users WHERE id = $1`, [userId]);
    await writeAudit(req.session, 'update', 'app_user', userId, { fullName, role, isActive, passwordChanged: Boolean(password) });
    res.json({ ok: true, user: result.rows[0] });
  } catch (error) { res.status(500).json({ ok: false, error: error.message }); }
});

app.delete('/api/users/:id', requireAdmin, async (req, res) => {
  try {
    const userId = Number(req.params.id);
    if (!userId) return res.status(400).json({ ok: false, error: 'Некорректный ID' });
    if (req.session.userId === userId) return res.status(400).json({ ok: false, error: 'Нельзя удалить самого себя' });
    const result = await db.query(`DELETE FROM app_users WHERE id = $1 RETURNING id, username`, [userId]);
    if (!result.rows.length) return res.status(404).json({ ok: false, error: 'Пользователь не найден' });
    await writeAudit(req.session, 'delete', 'app_user', userId, { username: result.rows[0].username });
    res.json({ ok: true, deletedId: userId });
  } catch (error) { res.status(500).json({ ok: false, error: error.message }); }
});

app.get('/api/health', requireAuth, async (req, res) => {
  try { const result = await db.query('SELECT NOW() AS now, current_database() AS database_name'); res.json({ ok: true, dbTime: result.rows[0].now, database: result.rows[0].database_name }); } catch (error) { res.status(500).json({ ok: false, error: error.message }); }
});

app.get('/api/meta', requireAuth, async (req, res) => {
  try {
    await ensureUsersTable(); await ensureAuditTable();
    const [studentsCount, teachersCount, resultsCount, calculationsCount, auditCount, usersCount] = await Promise.all([
      db.query('SELECT COUNT(*)::int AS count FROM students'),
      db.query('SELECT COUNT(*)::int AS count FROM teachers'),
      db.query('SELECT COUNT(*)::int AS count FROM student_results'),
      db.query('SELECT COUNT(*)::int AS count FROM teacher_calculations'),
      db.query('SELECT COUNT(*)::int AS count FROM audit_log'),
      db.query('SELECT COUNT(*)::int AS count FROM app_users')
    ]);
    res.json({ ok: true, stats: {
      students: studentsCount.rows[0].count,
      teachers: teachersCount.rows[0].count,
      results: resultsCount.rows[0].count,
      calculations: calculationsCount.rows[0].count,
      audit: auditCount.rows[0].count,
      users: usersCount.rows[0].count
    }});
  } catch (error) { res.status(500).json({ ok: false, error: error.message }); }
});

app.get('/api/form-options', requireAuth, async (req, res) => {
  try {
    const [studentsRes, criteriaRes, periodRes] = await Promise.all([
      db.query(`SELECT id, full_name FROM students ORDER BY full_name`),
      db.query(`SELECT id, name, base_score FROM criteria WHERE is_active = TRUE ORDER BY sort_order, name`),
      db.query(`SELECT id, name FROM academic_periods WHERE name = $1 LIMIT 1`, [PERIOD_NAME])
    ]);
    if (!periodRes.rows.length) return res.status(404).json({ ok: false, error: `Не найден период ${PERIOD_NAME}` });
    res.json({ ok: true, period: periodRes.rows[0], students: studentsRes.rows, criteria: criteriaRes.rows, gradeTracks: [
      { value: 'regular', label: 'Обычный' }, { value: 'course', label: '11 класс (курс)' }, { value: 'practicum', label: '11 класс (практикум)' }
    ]});
  } catch (error) { res.status(500).json({ ok: false, error: error.message }); }
});

app.get('/api/results', requireAuth, async (req, res) => {
  try { const result = await db.query(`SELECT sr.id, sr.student_id, sr.criterion_id, s.full_name AS student_name, c.name AS criterion_name, sr.grade_at_result, sr.grade_track, sr.base_score, sr.dynamic_bonus, sr.total_score, sr.raw_result_value, sr.result_date, sr.comment, sr.source_type FROM student_results sr JOIN students s ON s.id = sr.student_id JOIN criteria c ON c.id = sr.criterion_id ORDER BY sr.id DESC LIMIT 300`); res.json({ ok: true, rows: result.rows }); } catch (error) { res.status(500).json({ ok: false, error: error.message }); }
});

app.get('/api/results/export.xlsx', requireAuth, async (req, res) => {
  try { const result = await db.query(`SELECT sr.id AS "ID", s.full_name AS "Ученик", c.name AS "Критерий", sr.grade_at_result AS "Класс", sr.grade_track AS "Трек", sr.base_score AS "База", sr.dynamic_bonus AS "Динамика", sr.total_score AS "Итог", sr.result_date AS "Дата", sr.source_type AS "Источник" FROM student_results sr JOIN students s ON s.id = sr.student_id JOIN criteria c ON c.id = sr.criterion_id ORDER BY sr.id DESC`); const wb = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(result.rows), 'Results'); sendWorkbook(res, wb, 'student_results.xlsx'); } catch (error) { res.status(500).json({ ok: false, error: error.message }); }
});

app.get('/api/summary', requireAuth, async (req, res) => {
  try { const result = await db.query(`SELECT academic_period, teacher_name, teacher_short_name, is_dismissed, student_count_with_results, total_student_count, raw_points, normalization_factor, normalized_points, normalized_share_percent, reverse_weight, employee_share, total_fund, dismissed_fund, distributable_fund, uvsotr_value, reverse_incentive_amount, normalized_fund_amount FROM v_teacher_stim_summary ORDER BY teacher_name`); res.json({ ok: true, rows: result.rows }); } catch (error) { res.status(500).json({ ok: false, error: error.message }); }
});

app.get('/api/summary/export.xlsx', requireAuth, async (req, res) => {
  try { const result = await db.query(`SELECT teacher_name AS "Педагог", student_count_with_results AS "С баллами", total_student_count AS "Всего", raw_points AS "Raw points", normalized_points AS "Normalized points", reverse_incentive_amount AS "Reverse incentive", normalized_fund_amount AS "Normalized fund", is_dismissed AS "Уволен" FROM v_teacher_stim_summary ORDER BY teacher_name`); const wb = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(result.rows), 'TeacherSummary'); sendWorkbook(res, wb, 'teacher_summary.xlsx'); } catch (error) { res.status(500).json({ ok: false, error: error.message }); }
});

app.get('/api/teacher-calculations', requireAuth, async (req, res) => {
  try { const result = await db.query(`SELECT tc.id, t.full_name AS teacher_name, tc.raw_points, tc.normalized_points, tc.reverse_weight, tc.employee_share, tc.uvsotr_amount, tc.final_amount, tc.student_count_with_results, tc.total_student_count, tc.is_dismissed_snapshot, tc.calculated_at FROM teacher_calculations tc JOIN teachers t ON t.id = tc.teacher_id JOIN academic_periods ap ON ap.id = tc.academic_period_id WHERE ap.name = $1 ORDER BY t.full_name`, [PERIOD_NAME]); res.json({ ok: true, rows: result.rows }); } catch (error) { res.status(500).json({ ok: false, error: error.message }); }
});

app.get('/api/teacher-card/:teacherName', requireAuth, async (req, res) => {
  try {
    const teacherName = req.params.teacherName;
    const [summaryRes, calcRes, itemsRes] = await Promise.all([
      db.query(`SELECT * FROM v_teacher_stim_summary WHERE teacher_name = $1 LIMIT 1`, [teacherName]),
      db.query(`SELECT tc.*, t.full_name AS teacher_name FROM teacher_calculations tc JOIN teachers t ON t.id = tc.teacher_id JOIN academic_periods ap ON ap.id = tc.academic_period_id WHERE t.full_name = $1 AND ap.name = $2 ORDER BY tc.calculated_at DESC LIMIT 1`, [teacherName, PERIOD_NAME]),
      db.query(`SELECT s.full_name AS student_name, c.name AS criterion_name, sr.total_score, sr.result_date FROM student_result_teacher_links l JOIN student_results sr ON sr.id = l.student_result_id JOIN students s ON s.id = sr.student_id JOIN criteria c ON c.id = sr.criterion_id JOIN teachers t ON t.id = l.teacher_id WHERE t.full_name = $1 ORDER BY sr.result_date DESC NULLS LAST, sr.id DESC LIMIT 100`, [teacherName])
    ]);
    res.json({ ok: true, summary: summaryRes.rows[0] || null, calculation: calcRes.rows[0] || null, items: itemsRes.rows });
  } catch (error) { res.status(500).json({ ok: false, error: error.message }); }
});

app.get('/api/teacher-card/:teacherName/export.xlsx', requireAuth, async (req, res) => {
  try {
    const teacherName = req.params.teacherName;
    const [summaryRes, calcRes, itemsRes] = await Promise.all([
      db.query(`SELECT teacher_name AS "Педагог", student_count_with_results AS "С баллами", total_student_count AS "Всего", raw_points AS "Raw points", normalized_points AS "Normalized points", normalized_fund_amount AS "Normalized fund", is_dismissed AS "Уволен" FROM v_teacher_stim_summary WHERE teacher_name = $1 LIMIT 1`, [teacherName]),
      db.query(`SELECT t.full_name AS "Педагог", tc.raw_points AS "Raw", tc.normalized_points AS "Normalized", tc.uvsotr_amount AS "UvSotr", tc.final_amount AS "Final amount", tc.calculated_at AS "Дата расчёта" FROM teacher_calculations tc JOIN teachers t ON t.id = tc.teacher_id JOIN academic_periods ap ON ap.id = tc.academic_period_id WHERE t.full_name = $1 AND ap.name = $2 ORDER BY tc.calculated_at DESC LIMIT 1`, [teacherName, PERIOD_NAME]),
      db.query(`SELECT s.full_name AS "Ученик", c.name AS "Критерий", sr.total_score AS "Итоговый балл", sr.result_date AS "Дата" FROM student_result_teacher_links l JOIN student_results sr ON sr.id = l.student_result_id JOIN students s ON s.id = sr.student_id JOIN criteria c ON c.id = sr.criterion_id JOIN teachers t ON t.id = l.teacher_id WHERE t.full_name = $1 ORDER BY sr.result_date DESC NULLS LAST, sr.id DESC`, [teacherName])
    ]);
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(summaryRes.rows), 'Summary');
    XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(calcRes.rows), 'Calculation');
    XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(itemsRes.rows), 'Items');
    sendWorkbook(res, wb, `teacher_card_${teacherName}.xlsx`);
  } catch (error) { res.status(500).json({ ok: false, error: error.message }); }
});

app.get('/api/audit-log', requireAdmin, async (req, res) => {
  try { await ensureAuditTable(); const result = await db.query(`SELECT id, actor_name, actor_role, action_type, entity_type, entity_id, details, created_at FROM audit_log ORDER BY id DESC LIMIT 300`); res.json({ ok: true, rows: result.rows }); } catch (error) { res.status(500).json({ ok: false, error: error.message }); }
});

app.post('/api/recalculate-summary', requireAdmin, async (req, res) => {
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    const periodRes = await client.query(`SELECT id FROM academic_periods WHERE name = $1 LIMIT 1`, [PERIOD_NAME]);
    if (!periodRes.rows.length) throw new Error(`Не найден период ${PERIOD_NAME}`);
    const academicPeriodId = periodRes.rows[0].id;
    await client.query(`DELETE FROM teacher_calculation_items tci USING teacher_calculations tc WHERE tc.id = tci.teacher_calculation_id AND tc.academic_period_id = $1`, [academicPeriodId]);
    await client.query(`DELETE FROM teacher_calculations WHERE academic_period_id = $1`, [academicPeriodId]);
    const summaryRes = await client.query(`SELECT teacher_name, raw_points, normalized_points, reverse_weight, employee_share, reverse_incentive_amount, student_count_with_results, total_student_count, normalized_fund_amount, is_dismissed FROM v_teacher_stim_summary WHERE academic_period = $1 ORDER BY teacher_name`, [PERIOD_NAME]);
    let inserted = 0;
    for (const row of summaryRes.rows) {
      const teacherRes = await client.query(`SELECT id FROM teachers WHERE full_name = $1 LIMIT 1`, [row.teacher_name]);
      if (!teacherRes.rows.length) continue;
      await client.query(`INSERT INTO teacher_calculations (academic_period_id, teacher_id, raw_points, normalized_points, reverse_weight, employee_share, uvsotr_amount, final_amount, student_count_with_results, total_student_count, avg_group_ratio, is_dismissed_snapshot) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NULL, $11)`, [academicPeriodId, teacherRes.rows[0].id, row.raw_points || 0, row.normalized_points || 0, row.reverse_weight || 0, row.employee_share || 0, row.reverse_incentive_amount || 0, row.normalized_fund_amount || 0, row.student_count_with_results || 0, row.total_student_count || 0, row.is_dismissed || false]);
      inserted += 1;
    }
    await client.query('COMMIT');
    await writeAudit(req.session, 'recalculate', 'teacher_calculations', academicPeriodId, { inserted, period: PERIOD_NAME });
    res.json({ ok: true, message: 'Сводка пересчитана и сохранена в teacher_calculations', inserted });
  } catch (error) { await client.query('ROLLBACK'); res.status(500).json({ ok: false, error: error.message }); } finally { client.release(); }
});

app.post('/api/student-results', requireAuth, async (req, res) => {
  const { studentId, criterionId, gradeAtResult, gradeTrack, dynamicBonus, rawResultValue, resultDate, comment } = req.body || {};
  if (!studentId || !criterionId || !gradeAtResult || !gradeTrack) return res.status(400).json({ ok: false, error: 'Обязательные поля: studentId, criterionId, gradeAtResult, gradeTrack' });
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    const periodRes = await client.query(`SELECT id FROM academic_periods WHERE name = $1 LIMIT 1`, [PERIOD_NAME]);
    if (!periodRes.rows.length) throw new Error(`Не найден период ${PERIOD_NAME}`);
    const academicPeriodId = periodRes.rows[0].id;
    const criterionRes = await client.query(`SELECT id, base_score FROM criteria WHERE id = $1 LIMIT 1`, [criterionId]);
    if (!criterionRes.rows.length) throw new Error('Критерий не найден');
    const criterion = criterionRes.rows[0];
    const enrollmentRes = await client.query(`SELECT id FROM student_enrollments WHERE student_id = $1 AND academic_period_id = $2 AND grade = $3 AND grade_track = $4::grade_track_type LIMIT 1`, [studentId, academicPeriodId, gradeAtResult, gradeTrack]);
    const studentEnrollmentId = enrollmentRes.rows[0]?.id || null;
    const insertRes = await client.query(`INSERT INTO student_results (academic_period_id, student_id, student_enrollment_id, criterion_id, grade_at_result, grade_track, base_score, dynamic_bonus, raw_result_value, result_date, source_type, comment) VALUES ($1, $2, $3, $4, $5, $6::grade_track_type, $7, $8, $9, $10, 'web_form', $11) RETURNING id, total_score`, [academicPeriodId, studentId, studentEnrollmentId, criterion.id, gradeAtResult, gradeTrack, criterion.base_score, Number(dynamicBonus || 0), rawResultValue || null, resultDate || null, comment || null]);
    await client.query('COMMIT');
    await writeAudit(req.session, 'create', 'student_result', insertRes.rows[0].id, await payloadFromReq(req));
    res.status(201).json({ ok: true, message: 'Результат успешно сохранён', result: insertRes.rows[0] });
  } catch (error) { await client.query('ROLLBACK'); res.status(500).json({ ok: false, error: error.message }); } finally { client.release(); }
});

app.put('/api/student-results/:id', requireAuth, async (req, res) => {
  const resultId = Number(req.params.id);
  const { studentId, criterionId, gradeAtResult, gradeTrack, dynamicBonus, rawResultValue, resultDate, comment } = req.body || {};
  if (!resultId) return res.status(400).json({ ok: false, error: 'Некорректный id результата' });
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    const existingRes = await client.query(`SELECT id, academic_period_id FROM student_results WHERE id = $1 LIMIT 1`, [resultId]);
    if (!existingRes.rows.length) throw new Error('Результат не найден');
    const academicPeriodId = existingRes.rows[0].academic_period_id;
    const criterionRes = await client.query(`SELECT id, base_score FROM criteria WHERE id = $1 LIMIT 1`, [criterionId]);
    if (!criterionRes.rows.length) throw new Error('Критерий не найден');
    const criterion = criterionRes.rows[0];
    const enrollmentRes = await client.query(`SELECT id FROM student_enrollments WHERE student_id = $1 AND academic_period_id = $2 AND grade = $3 AND grade_track = $4::grade_track_type LIMIT 1`, [studentId, academicPeriodId, gradeAtResult, gradeTrack]);
    const studentEnrollmentId = enrollmentRes.rows[0]?.id || null;
    const updateRes = await client.query(`UPDATE student_results SET student_id = $2, student_enrollment_id = $3, criterion_id = $4, grade_at_result = $5, grade_track = $6::grade_track_type, base_score = $7, dynamic_bonus = $8, raw_result_value = $9, result_date = $10, comment = $11, source_type = 'web_form_edit' WHERE id = $1 RETURNING id, total_score`, [resultId, studentId, studentEnrollmentId, criterion.id, gradeAtResult, gradeTrack, criterion.base_score, Number(dynamicBonus || 0), rawResultValue || null, resultDate || null, comment || null]);
    await client.query('COMMIT');
    await writeAudit(req.session, 'update', 'student_result', resultId, await payloadFromReq(req));
    res.json({ ok: true, message: 'Результат обновлён', result: updateRes.rows[0] });
  } catch (error) { await client.query('ROLLBACK'); res.status(500).json({ ok: false, error: error.message }); } finally { client.release(); }
});

app.delete('/api/student-results/:id', requireAdmin, async (req, res) => {
  const resultId = Number(req.params.id);
  if (!resultId) return res.status(400).json({ ok: false, error: 'Некорректный id результата' });
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    await client.query(`DELETE FROM teacher_calculation_items WHERE student_result_id = $1`, [resultId]);
    await client.query(`DELETE FROM student_result_teacher_links WHERE student_result_id = $1`, [resultId]);
    const deleteRes = await client.query(`DELETE FROM student_results WHERE id = $1 RETURNING id`, [resultId]);
    if (!deleteRes.rows.length) throw new Error('Результат не найден');
    await client.query('COMMIT');
    await writeAudit(req.session, 'delete', 'student_result', resultId, {});
    res.json({ ok: true, message: 'Результат удалён', deletedId: resultId });
  } catch (error) { await client.query('ROLLBACK'); res.status(500).json({ ok: false, error: error.message }); } finally { client.release(); }
});

app.get('*', async (req, res) => { await seedInitialAdmin(); res.sendFile(path.join(__dirname, 'public', 'index.html')); });

seedInitialAdmin().then(() => {
  app.listen(PORT, '0.0.0.0', () => console.log(`STIMUL mini app users started on port ${PORT}`));
}).catch((error) => {
  console.error('Failed to seed initial admin:', error.message);
  process.exit(1);
});
