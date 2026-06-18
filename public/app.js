const loginScreen = document.getElementById('loginScreen');
const appRoot = document.getElementById('appRoot');
const loginForm = document.getElementById('loginForm');
const loginStatus = document.getElementById('loginStatus');
const loginUsername = document.getElementById('loginUsername');
const loginPassword = document.getElementById('loginPassword');
const currentUserName = document.getElementById('currentUserName');
const currentUserRole = document.getElementById('currentUserRole');
const statusBox = document.getElementById('statusBox');
const periodName = document.getElementById('periodName');
const pageTitle = document.getElementById('pageTitle');
const resultsTable = document.getElementById('resultsTable');
const summaryTable = document.getElementById('summaryTable');
const savedTable = document.getElementById('savedTable');
const auditTable = document.getElementById('auditTable');
const usersTable = document.getElementById('usersTable');
const formStatus = document.getElementById('formStatus');
const userFormStatus = document.getElementById('userFormStatus');
const formTitle = document.getElementById('formTitle');
const userFormTitle = document.getElementById('userFormTitle');
const submitBtn = document.getElementById('submitBtn');
const userSubmitBtn = document.getElementById('userSubmitBtn');
const resultsMeta = document.getElementById('resultsMeta');
const summaryMeta = document.getElementById('summaryMeta');
const savedMeta = document.getElementById('savedMeta');
const auditMeta = document.getElementById('auditMeta');
const usersMeta = document.getElementById('usersMeta');
const teacherCardMeta = document.getElementById('teacherCardMeta');
const teacherSummaryInfo = document.getElementById('teacherSummaryInfo');
const teacherCalcInfo = document.getElementById('teacherCalcInfo');
const teacherItemsTable = document.getElementById('teacherItemsTable');
const teacherSelect = document.getElementById('teacherSelect');
const studentsCount = document.getElementById('studentsCount');
const teachersCount = document.getElementById('teachersCount');
const resultsCount = document.getElementById('resultsCount');
const calculationsCount = document.getElementById('calculationsCount');
const auditCount = document.getElementById('auditCount');
const usersCount = document.getElementById('usersCount');
const resultId = document.getElementById('resultId');
const studentId = document.getElementById('studentId');
const criterionId = document.getElementById('criterionId');
const gradeAtResult = document.getElementById('gradeAtResult');
const gradeTrack = document.getElementById('gradeTrack');
const dynamicBonus = document.getElementById('dynamicBonus');
const rawResultValue = document.getElementById('rawResultValue');
const resultDate = document.getElementById('resultDate');
const comment = document.getElementById('comment');
const resultForm = document.getElementById('resultForm');
const resultsSearch = document.getElementById('resultsSearch');
const resultsTrackFilter = document.getElementById('resultsTrackFilter');
const resultsGradeFilter = document.getElementById('resultsGradeFilter');
const summarySearch = document.getElementById('summarySearch');
const hideDismissed = document.getElementById('hideDismissed');
const savedSearch = document.getElementById('savedSearch');
const userForm = document.getElementById('userForm');
const userId = document.getElementById('userId');
const userUsername = document.getElementById('userUsername');
const userFullName = document.getElementById('userFullName');
const userRole = document.getElementById('userRole');
const userPassword = document.getElementById('userPassword');
const userIsActive = document.getElementById('userIsActive');

let currentUser = null;
let resultsCache = [];
let summaryCache = [];
let savedCache = [];
let auditCache = [];
let usersCache = [];

async function fetchJson(url, options) {
  const res = await fetch(url, options);
  const data = await res.json();
  if (!res.ok || data.ok === false) throw new Error(data.error || 'Ошибка запроса');
  return data;
}
function formatNumber(value) {
  if (value === null || value === undefined || value === '') return '—';
  const num = Number(value);
  if (Number.isNaN(num)) return String(value);
  return new Intl.NumberFormat('ru-RU', { maximumFractionDigits: 4 }).format(num);
}
function setSelectOptions(select, items, mapFn, placeholder) {
  const options = [];
  if (placeholder) options.push(`<option value="">${placeholder}</option>`);
  options.push(...items.map(mapFn));
  select.innerHTML = options.join('');
}
function showView(viewName) {
  document.querySelectorAll('.view').forEach((view) => view.classList.remove('active-view'));
  document.querySelectorAll('.nav-btn[data-view]').forEach((btn) => btn.classList.remove('active'));
  document.getElementById(`${viewName}View`).classList.add('active-view');
  document.querySelector(`.nav-btn[data-view="${viewName}"]`)?.classList.add('active');
  pageTitle.textContent = ({ dashboard: 'Главная', results: 'Результаты', summary: 'Сводка', teacher: 'Карточка педагога', audit: 'Журнал', users: 'Пользователи' })[viewName] || 'STIMUL';
}
function resetForm() {
  resultId.value = '';
  resultForm.reset();
  formTitle.textContent = 'Новый результат';
  submitBtn.textContent = 'Сохранить результат';
  formStatus.textContent = 'Форма сброшена.';
}
function resetUserForm() {
  userId.value = '';
  userForm.reset();
  userRole.value = 'admin';
  userIsActive.value = 'true';
  userFormTitle.textContent = 'Новый пользователь';
  userSubmitBtn.textContent = 'Сохранить пользователя';
  userFormStatus.textContent = 'Форма пользователя сброшена.';
  userUsername.disabled = false;
}
function applyRoleUi() {
  currentUserName.textContent = currentUser?.fullName || currentUser?.username || '—';
  currentUserRole.textContent = currentUser?.role || '—';
  const adminOnly = currentUser?.role === 'admin';
  document.getElementById('recalculateBtn').style.display = adminOnly ? 'inline-flex' : 'none';
  document.querySelector('.nav-btn[data-view="audit"]').style.display = adminOnly ? 'block' : 'none';
  document.querySelector('.nav-btn[data-view="users"]').style.display = adminOnly ? 'block' : 'none';
}
function fillForm(row) {
  resultId.value = row.id;
  studentId.value = row.student_id;
  criterionId.value = row.criterion_id;
  gradeAtResult.value = row.grade_at_result;
  gradeTrack.value = row.grade_track;
  dynamicBonus.value = row.dynamic_bonus ?? 0;
  rawResultValue.value = row.raw_result_value ?? '';
  resultDate.value = row.result_date ? row.result_date.slice(0, 10) : '';
  comment.value = row.comment ?? '';
  formTitle.textContent = `Редактирование результата #${row.id}`;
  submitBtn.textContent = 'Сохранить изменения';
  formStatus.textContent = `Вы редактируете результат #${row.id}.`;
  showView('results');
}
function fillUserForm(row) {
  userId.value = row.id;
  userUsername.value = row.username;
  userFullName.value = row.full_name;
  userRole.value = row.role;
  userIsActive.value = String(row.is_active);
  userPassword.value = '';
  userFormTitle.textContent = `Редактирование пользователя #${row.id}`;
  userSubmitBtn.textContent = 'Сохранить изменения';
  userFormStatus.textContent = `Редактируется пользователь ${row.username}. Пароль заполняйте только если хотите заменить.`;
  userUsername.disabled = true;
  showView('users');
}
async function login(username, password) {
  const data = await fetchJson('/api/login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ username, password }) });
  currentUser = data.user;
  loginScreen.style.display = 'none';
  appRoot.style.display = 'grid';
  applyRoleUi();
  await bootstrapApp();
}
async function checkMe() {
  try {
    const data = await fetchJson('/api/me');
    currentUser = data.user;
    loginScreen.style.display = 'none';
    appRoot.style.display = 'grid';
    applyRoleUi();
    await bootstrapApp();
  } catch {
    loginScreen.style.display = 'grid';
    appRoot.style.display = 'none';
  }
}
async function loadHealth() { try { statusBox.textContent = JSON.stringify(await fetchJson('/api/health'), null, 2); } catch (e) { statusBox.textContent = e.message; } }
async function loadMeta() {
  try {
    const data = await fetchJson('/api/meta');
    studentsCount.textContent = data.stats.students;
    teachersCount.textContent = data.stats.teachers;
    resultsCount.textContent = data.stats.results;
    calculationsCount.textContent = data.stats.calculations;
    auditCount.textContent = data.stats.audit;
    usersCount.textContent = data.stats.users;
  } catch {
    studentsCount.textContent = teachersCount.textContent = resultsCount.textContent = calculationsCount.textContent = auditCount.textContent = usersCount.textContent = 'Ошибка';
  }
}
async function loadOptions() {
  try {
    const data = await fetchJson('/api/form-options');
    periodName.textContent = data.period.name;
    setSelectOptions(studentId, data.students, (item) => `<option value="${item.id}">${item.full_name}</option>`, 'Выберите ученика');
    setSelectOptions(criterionId, data.criteria, (item) => `<option value="${item.id}">${item.name} (база: ${item.base_score})</option>`, 'Выберите критерий');
    setSelectOptions(gradeTrack, data.gradeTracks, (item) => `<option value="${item.value}">${item.label}</option>`, 'Выберите трек');
  } catch (error) { formStatus.textContent = error.message; }
}
function renderResultsTable() {
  const q = resultsSearch.value.trim().toLowerCase();
  const track = resultsTrackFilter.value;
  const grade = resultsGradeFilter.value;
  const filtered = resultsCache.filter((row) => (!q || row.student_name.toLowerCase().includes(q) || row.criterion_name.toLowerCase().includes(q)) && (!track || row.grade_track === track) && (!grade || String(row.grade_at_result) === grade));
  resultsMeta.textContent = `Показано ${filtered.length} из ${resultsCache.length}`;
  if (!filtered.length) return resultsTable.innerHTML = '<p class="muted">Ничего не найдено</p>';
  const canDelete = currentUser?.role === 'admin';
  resultsTable.innerHTML = `<table><thead><tr><th>ID</th><th>Ученик</th><th>Критерий</th><th>Класс</th><th>Трек</th><th>Итог</th><th>Дата</th><th>Действия</th></tr></thead><tbody>${filtered.map((row) => `<tr><td>${row.id}</td><td>${row.student_name}</td><td>${row.criterion_name}</td><td>${row.grade_at_result}</td><td>${row.grade_track}</td><td>${formatNumber(row.total_score)}</td><td>${row.result_date || '—'}</td><td><div class="row-actions"><button class="secondary" data-action="edit" data-id="${row.id}">Редактировать</button>${canDelete ? `<button class="danger" data-action="delete" data-id="${row.id}">Удалить</button>` : ''}</div></td></tr>`).join('')}</tbody></table>`;
}
function renderSummaryTable() {
  const q = summarySearch.value.trim().toLowerCase();
  const filtered = summaryCache.filter((row) => (!q || row.teacher_name.toLowerCase().includes(q)) && (!hideDismissed.checked || !row.is_dismissed));
  summaryMeta.textContent = `Показано ${filtered.length} из ${summaryCache.length}`;
  if (!filtered.length) return summaryTable.innerHTML = '<p class="muted">Ничего не найдено</p>';
  summaryTable.innerHTML = `<table><thead><tr><th>Педагог</th><th>С баллами</th><th>Всего</th><th>Raw</th><th>Normalized</th><th>Normalized fund</th><th>Открыть</th></tr></thead><tbody>${filtered.map((row) => `<tr><td>${row.teacher_name}</td><td>${formatNumber(row.student_count_with_results)}</td><td>${formatNumber(row.total_student_count)}</td><td>${formatNumber(row.raw_points)}</td><td>${formatNumber(row.normalized_points)}</td><td>${formatNumber(row.normalized_fund_amount)}</td><td><button class="secondary" data-open-teacher="${encodeURIComponent(row.teacher_name)}">Карточка</button></td></tr>`).join('')}</tbody></table>`;
}
function renderSavedTable() {
  const q = savedSearch.value.trim().toLowerCase();
  const filtered = savedCache.filter((row) => !q || row.teacher_name.toLowerCase().includes(q));
  savedMeta.textContent = `Показано ${filtered.length} из ${savedCache.length}`;
  setSelectOptions(teacherSelect, filtered, (item) => `<option value="${item.teacher_name}">${item.teacher_name}</option>`, 'Выберите педагога');
  if (!filtered.length) return savedTable.innerHTML = '<p class="muted">Ничего не найдено</p>';
  savedTable.innerHTML = `<table><thead><tr><th>Педагог</th><th>Raw</th><th>Normalized</th><th>UvSotr</th><th>Final amount</th><th>Дата расчёта</th><th>Открыть</th></tr></thead><tbody>${filtered.map((row) => `<tr><td>${row.teacher_name}</td><td>${formatNumber(row.raw_points)}</td><td>${formatNumber(row.normalized_points)}</td><td>${formatNumber(row.uvsotr_amount)}</td><td>${formatNumber(row.final_amount)}</td><td>${row.calculated_at || '—'}</td><td><button class="secondary" data-open-teacher="${encodeURIComponent(row.teacher_name)}">Карточка</button></td></tr>`).join('')}</tbody></table>`;
}
function renderAuditTable() {
  auditMeta.textContent = `Показано ${auditCache.length} событий`;
  if (!auditCache.length) return auditTable.innerHTML = '<p class="muted">Журнал пуст</p>';
  auditTable.innerHTML = `<table><thead><tr><th>ID</th><th>Кто</th><th>Роль</th><th>Действие</th><th>Сущность</th><th>ID сущности</th><th>Время</th></tr></thead><tbody>${auditCache.map((row) => `<tr><td>${row.id}</td><td>${row.actor_name}</td><td>${row.actor_role}</td><td>${row.action_type}</td><td>${row.entity_type}</td><td>${row.entity_id || '—'}</td><td>${row.created_at}</td></tr>`).join('')}</tbody></table>`;
}
function renderUsersTable() {
  usersMeta.textContent = `Показано ${usersCache.length} пользователей`;
  if (!usersCache.length) return usersTable.innerHTML = '<p class="muted">Пользователи не найдены</p>';
  usersTable.innerHTML = `<table><thead><tr><th>ID</th><th>Логин</th><th>ФИО</th><th>Роль</th><th>Статус</th><th>Последний вход</th><th>Действия</th></tr></thead><tbody>${usersCache.map((row) => `<tr><td>${row.id}</td><td>${row.username}</td><td>${row.full_name}</td><td>${row.role}</td><td>${row.is_active ? 'Активен' : 'Отключён'}</td><td>${row.last_login_at || '—'}</td><td><div class="row-actions"><button class="secondary" data-user-action="edit" data-id="${row.id}">Редактировать</button>${currentUser?.userId !== row.id ? `<button class="danger" data-user-action="delete" data-id="${row.id}">Удалить</button>` : ''}</div></td></tr>`).join('')}</tbody></table>`;
}
async function loadResults() { try { const data = await fetchJson('/api/results'); resultsCache = data.rows; renderResultsTable(); } catch (e) { resultsTable.innerHTML = `<p class="muted">Ошибка: ${e.message}</p>`; } }
async function loadSummary() { try { const data = await fetchJson('/api/summary'); summaryCache = data.rows; renderSummaryTable(); } catch (e) { summaryTable.innerHTML = `<p class="muted">Ошибка: ${e.message}</p>`; } }
async function loadSavedCalculations() { try { const data = await fetchJson('/api/teacher-calculations'); savedCache = data.rows; renderSavedTable(); } catch (e) { savedTable.innerHTML = `<p class="muted">Ошибка: ${e.message}</p>`; } }
async function loadAudit() { try { const data = await fetchJson('/api/audit-log'); auditCache = data.rows; renderAuditTable(); } catch (e) { auditTable.innerHTML = `<p class="muted">${e.message}</p>`; auditMeta.textContent = 'Журнал недоступен'; } }
async function loadUsers() { try { const data = await fetchJson('/api/users'); usersCache = data.rows; renderUsersTable(); } catch (e) { usersTable.innerHTML = `<p class="muted">${e.message}</p>`; usersMeta.textContent = 'Раздел недоступен'; } }
async function loadTeacherCard(teacherName) {
  if (!teacherName) return teacherCardMeta.textContent = 'Выберите педагога.';
  try {
    const data = await fetchJson(`/api/teacher-card/${encodeURIComponent(teacherName)}`);
    showView('teacher');
    teacherSelect.value = teacherName;
    teacherCardMeta.innerHTML = `Карточка педагога: ${teacherName} <span class="teacher-card-actions"><button class="secondary" id="printTeacherBtn">Печать карточки</button> <a class="button-link" href="/api/teacher-card/${encodeURIComponent(teacherName)}/export.xlsx" target="_blank" rel="noopener noreferrer">Экспорт XLSX</a></span>`;
    teacherSummaryInfo.innerHTML = data.summary ? `<p><strong>С баллами:</strong> ${formatNumber(data.summary.student_count_with_results)}</p><p><strong>Всего учеников:</strong> ${formatNumber(data.summary.total_student_count)}</p><p><strong>Raw points:</strong> ${formatNumber(data.summary.raw_points)}</p><p><strong>Normalized points:</strong> ${formatNumber(data.summary.normalized_points)}</p><p><strong>Normalized fund:</strong> ${formatNumber(data.summary.normalized_fund_amount)}</p><p><strong>Уволен:</strong> ${data.summary.is_dismissed ? 'Да' : 'Нет'}</p>` : '<p class="muted">Нет данных summary view</p>';
    teacherCalcInfo.innerHTML = data.calculation ? `<p><strong>Raw:</strong> ${formatNumber(data.calculation.raw_points)}</p><p><strong>Normalized:</strong> ${formatNumber(data.calculation.normalized_points)}</p><p><strong>UvSotr:</strong> ${formatNumber(data.calculation.uvsotr_amount)}</p><p><strong>Final amount:</strong> ${formatNumber(data.calculation.final_amount)}</p><p><strong>Дата расчёта:</strong> ${data.calculation.calculated_at || '—'}</p>` : '<p class="muted">Нет сохранённого расчёта</p>';
    teacherItemsTable.innerHTML = data.items.length ? `<table><thead><tr><th>Ученик</th><th>Критерий</th><th>Итоговый балл</th><th>Дата</th></tr></thead><tbody>${data.items.map((row) => `<tr><td>${row.student_name}</td><td>${row.criterion_name}</td><td>${formatNumber(row.total_score)}</td><td>${row.result_date || '—'}</td></tr>`).join('')}</tbody></table>` : '<p class="muted">Нет связанных результатов</p>';
    document.getElementById('printTeacherBtn').addEventListener('click', () => window.print());
  } catch (e) { teacherCardMeta.textContent = e.message; }
}
async function recalculateSummary() {
  statusBox.textContent = 'Пересчитываем сводку...';
  try { const data = await fetchJson('/api/recalculate-summary', { method: 'POST' }); statusBox.textContent = JSON.stringify(data, null, 2); await bootstrapData(); } catch (e) { statusBox.textContent = e.message; }
}
async function bootstrapData() {
  await Promise.all([
    loadMeta(), loadHealth(), loadOptions(), loadResults(), loadSummary(), loadSavedCalculations(),
    currentUser?.role === 'admin' ? loadAudit() : Promise.resolve(),
    currentUser?.role === 'admin' ? loadUsers() : Promise.resolve()
  ]);
}
async function bootstrapApp() { applyRoleUi(); await bootstrapData(); }
loginForm.addEventListener('submit', async (e) => {
  e.preventDefault(); loginStatus.textContent = 'Входим...';
  try { await login(loginUsername.value, loginPassword.value); loginStatus.textContent = 'Успешный вход'; } catch (err) { loginStatus.textContent = err.message; }
});
document.getElementById('logoutBtn').addEventListener('click', async () => {
  try { await fetchJson('/api/logout', { method: 'POST' }); } catch {}
  currentUser = null; loginScreen.style.display = 'grid'; appRoot.style.display = 'none';
});
document.querySelectorAll('.nav-btn[data-view]').forEach((btn) => btn.addEventListener('click', () => showView(btn.dataset.view)));
document.getElementById('checkHealthBtn').addEventListener('click', loadHealth);
document.getElementById('recalculateBtn').addEventListener('click', recalculateSummary);
document.getElementById('resetFormBtn').addEventListener('click', resetForm);
document.getElementById('loadResultsBtn').addEventListener('click', loadResults);
document.getElementById('loadSummaryBtn').addEventListener('click', loadSummary);
document.getElementById('loadSavedBtn').addEventListener('click', loadSavedCalculations);
document.getElementById('loadTeacherCardBtn').addEventListener('click', () => loadTeacherCard(teacherSelect.value));
document.getElementById('loadAuditBtn').addEventListener('click', loadAudit);
document.getElementById('loadUsersBtn').addEventListener('click', loadUsers);
document.getElementById('resetUserFormBtn').addEventListener('click', resetUserForm);
resultsSearch.addEventListener('input', renderResultsTable);
resultsTrackFilter.addEventListener('change', renderResultsTable);
resultsGradeFilter.addEventListener('change', renderResultsTable);
summarySearch.addEventListener('input', renderSummaryTable);
hideDismissed.addEventListener('change', renderSummaryTable);
savedSearch.addEventListener('input', renderSavedTable);
resultsTable.addEventListener('click', async (event) => {
  const actionButton = event.target.closest('button[data-action]'); if (!actionButton) return;
  const id = Number(actionButton.dataset.id); const action = actionButton.dataset.action; const row = resultsCache.find((item) => item.id === id); if (!row) return;
  if (action === 'edit') return fillForm(row);
  if (action === 'delete') {
    const confirmed = window.confirm(`Удалить результат #${id} (${row.student_name})?`); if (!confirmed) return;
    try { const data = await fetchJson(`/api/student-results/${id}`, { method: 'DELETE' }); formStatus.textContent = JSON.stringify(data, null, 2); if (resultId.value === String(id)) resetForm(); await bootstrapData(); } catch (error) { formStatus.textContent = error.message; }
  }
});
summaryTable.addEventListener('click', (event) => { const btn = event.target.closest('button[data-open-teacher]'); if (btn) loadTeacherCard(decodeURIComponent(btn.dataset.openTeacher)); });
savedTable.addEventListener('click', (event) => { const btn = event.target.closest('button[data-open-teacher]'); if (btn) loadTeacherCard(decodeURIComponent(btn.dataset.openTeacher)); });
resultForm.addEventListener('submit', async (event) => {
  event.preventDefault(); formStatus.textContent = 'Сохраняем...';
  const payload = { studentId: Number(studentId.value), criterionId: Number(criterionId.value), gradeAtResult: Number(gradeAtResult.value), gradeTrack: gradeTrack.value, dynamicBonus: dynamicBonus.value, rawResultValue: rawResultValue.value, resultDate: resultDate.value, comment: comment.value };
  const id = resultId.value; const isEdit = Boolean(id);
  try { const data = await fetchJson(isEdit ? `/api/student-results/${id}` : '/api/student-results', { method: isEdit ? 'PUT' : 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) }); formStatus.textContent = JSON.stringify(data, null, 2); resetForm(); await bootstrapData(); } catch (error) { formStatus.textContent = error.message; }
});
usersTable.addEventListener('click', async (event) => {
  const btn = event.target.closest('button[data-user-action]'); if (!btn) return;
  const id = Number(btn.dataset.id); const action = btn.dataset.userAction; const row = usersCache.find((item) => item.id === id); if (!row) return;
  if (action === 'edit') return fillUserForm(row);
  if (action === 'delete') {
    const confirmed = window.confirm(`Удалить пользователя ${row.username}?`); if (!confirmed) return;
    try { const data = await fetchJson(`/api/users/${id}`, { method: 'DELETE' }); userFormStatus.textContent = JSON.stringify(data, null, 2); await bootstrapData(); } catch (error) { userFormStatus.textContent = error.message; }
  }
});
userForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  userFormStatus.textContent = 'Сохраняем пользователя...';
  const id = userId.value;
  const isEdit = Boolean(id);
  const payload = {
    username: userUsername.value,
    fullName: userFullName.value,
    role: userRole.value,
    password: userPassword.value,
    isActive: userIsActive.value === 'true'
  };
  if (!isEdit && !payload.password) return userFormStatus.textContent = 'Для нового пользователя нужен пароль';
  try {
    const data = await fetchJson(isEdit ? `/api/users/${id}` : '/api/users', {
      method: isEdit ? 'PUT' : 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload)
    });
    userFormStatus.textContent = JSON.stringify(data, null, 2);
    resetUserForm();
    await bootstrapData();
  } catch (error) { userFormStatus.textContent = error.message; }
});
checkMe();
