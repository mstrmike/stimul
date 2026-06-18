BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'grade_track_type') THEN
        CREATE TYPE grade_track_type AS ENUM ('regular', 'course', 'practicum');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'assignment_type_enum') THEN
        CREATE TYPE assignment_type_enum AS ENUM ('main', 'co_teacher', 'curator', 'other');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role_enum') THEN
        CREATE TYPE user_role_enum AS ENUM ('admin', 'operator', 'viewer');
    END IF;
END$$;

CREATE TABLE IF NOT EXISTS academic_periods (
    id                  BIGSERIAL PRIMARY KEY,
    name                VARCHAR(100) NOT NULL,
    date_start          DATE NOT NULL,
    date_end            DATE NOT NULL,
    is_closed           BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT academic_periods_dates_chk CHECK (date_end >= date_start),
    CONSTRAINT academic_periods_name_uniq UNIQUE (name)
);

CREATE TABLE IF NOT EXISTS students (
    id                  BIGSERIAL PRIMARY KEY,
    full_name           VARCHAR(255) NOT NULL,
    last_name           VARCHAR(100),
    first_name          VARCHAR(100),
    middle_name         VARCHAR(100),
    full_name_normalized VARCHAR(255) GENERATED ALWAYS AS (
        lower(regexp_replace(btrim(full_name), '\s+', ' ', 'g'))
    ) STORED,
    birth_date          DATE,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_students_full_name ON students(full_name);
CREATE INDEX IF NOT EXISTS idx_students_full_name_normalized ON students(full_name_normalized);

CREATE TABLE IF NOT EXISTS teachers (
    id                  BIGSERIAL PRIMARY KEY,
    full_name           VARCHAR(255) NOT NULL,
    short_name          VARCHAR(150),
    full_name_normalized VARCHAR(255) GENERATED ALWAYS AS (
        lower(regexp_replace(btrim(full_name), '\s+', ' ', 'g'))
    ) STORED,
    is_dismissed        BOOLEAN NOT NULL DEFAULT FALSE,
    dismissed_at        DATE,
    comment             TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT teachers_dismissed_date_chk CHECK (
        (is_dismissed = FALSE) OR (dismissed_at IS NOT NULL) OR (full_name = 'Уволившиеся')
    )
);

CREATE INDEX IF NOT EXISTS idx_teachers_full_name ON teachers(full_name);
CREATE INDEX IF NOT EXISTS idx_teachers_full_name_normalized ON teachers(full_name_normalized);

CREATE TABLE IF NOT EXISTS users (
    id                  BIGSERIAL PRIMARY KEY,
    login               VARCHAR(100) NOT NULL UNIQUE,
    password_hash       VARCHAR(255) NOT NULL,
    full_name           VARCHAR(255) NOT NULL,
    role                user_role_enum NOT NULL DEFAULT 'viewer',
    teacher_id          BIGINT REFERENCES teachers(id) ON DELETE SET NULL,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS student_enrollments (
    id                  BIGSERIAL PRIMARY KEY,
    student_id          BIGINT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    academic_period_id  BIGINT NOT NULL REFERENCES academic_periods(id) ON DELETE CASCADE,
    grade               SMALLINT NOT NULL,
    grade_label         VARCHAR(50),
    class_letter        VARCHAR(10),
    grade_track         grade_track_type NOT NULL DEFAULT 'regular',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT student_enrollments_grade_chk CHECK (grade BETWEEN 2 AND 11),
    CONSTRAINT student_enrollments_uniq UNIQUE (
        student_id, academic_period_id, grade, grade_track, class_letter
    )
);

CREATE INDEX IF NOT EXISTS idx_student_enrollments_student ON student_enrollments(student_id);
CREATE INDEX IF NOT EXISTS idx_student_enrollments_period_grade ON student_enrollments(academic_period_id, grade);

CREATE TABLE IF NOT EXISTS criterion_groups (
    id                  BIGSERIAL PRIMARY KEY,
    code                VARCHAR(50) NOT NULL UNIQUE,
    name                VARCHAR(255) NOT NULL,
    description         TEXT,
    sort_order          INTEGER NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS criteria (
    id                  BIGSERIAL PRIMARY KEY,
    criterion_group_id  BIGINT NOT NULL REFERENCES criterion_groups(id) ON DELETE RESTRICT,
    code                VARCHAR(100),
    name                VARCHAR(255) NOT NULL,
    raw_value_label     VARCHAR(100),
    base_score          NUMERIC(12,4) NOT NULL,
    max_dynamic_bonus   NUMERIC(12,4),
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order          INTEGER NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT criteria_base_score_chk CHECK (base_score >= 0),
    CONSTRAINT criteria_max_dynamic_bonus_chk CHECK (max_dynamic_bonus IS NULL OR max_dynamic_bonus >= 0),
    CONSTRAINT criteria_code_uniq UNIQUE (code)
);

CREATE INDEX IF NOT EXISTS idx_criteria_group ON criteria(criterion_group_id);
CREATE INDEX IF NOT EXISTS idx_criteria_name ON criteria(name);

CREATE TABLE IF NOT EXISTS criterion_grade_weights (
    id                  BIGSERIAL PRIMARY KEY,
    criterion_id        BIGINT NOT NULL REFERENCES criteria(id) ON DELETE CASCADE,
    grade               SMALLINT NOT NULL,
    grade_track         grade_track_type NOT NULL DEFAULT 'regular',
    weight_value        NUMERIC(12,6) NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT criterion_grade_weights_grade_chk CHECK (grade BETWEEN 2 AND 11),
    CONSTRAINT criterion_grade_weights_value_chk CHECK (weight_value >= 0),
    CONSTRAINT criterion_grade_weights_uniq UNIQUE (criterion_id, grade, grade_track)
);

CREATE INDEX IF NOT EXISTS idx_criterion_grade_weights_grade ON criterion_grade_weights(grade, grade_track);

CREATE TABLE IF NOT EXISTS student_teacher_assignments (
    id                  BIGSERIAL PRIMARY KEY,
    student_id          BIGINT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    teacher_id          BIGINT NOT NULL REFERENCES teachers(id) ON DELETE RESTRICT,
    academic_period_id  BIGINT NOT NULL REFERENCES academic_periods(id) ON DELETE CASCADE,
    grade               SMALLINT NOT NULL,
    grade_track         grade_track_type NOT NULL DEFAULT 'regular',
    assignment_type     assignment_type_enum NOT NULL DEFAULT 'main',
    share_percent       NUMERIC(5,2) NOT NULL DEFAULT 100.00,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT student_teacher_assignments_grade_chk CHECK (grade BETWEEN 2 AND 11),
    CONSTRAINT student_teacher_assignments_share_chk CHECK (share_percent > 0 AND share_percent <= 100),
    CONSTRAINT student_teacher_assignments_uniq UNIQUE (
        student_id, teacher_id, academic_period_id, grade, grade_track, assignment_type
    )
);

CREATE INDEX IF NOT EXISTS idx_student_teacher_assignments_student ON student_teacher_assignments(student_id);
CREATE INDEX IF NOT EXISTS idx_student_teacher_assignments_teacher ON student_teacher_assignments(teacher_id);
CREATE INDEX IF NOT EXISTS idx_student_teacher_assignments_period_grade ON student_teacher_assignments(academic_period_id, grade, grade_track);

CREATE TABLE IF NOT EXISTS student_results (
    id                  BIGSERIAL PRIMARY KEY,
    academic_period_id  BIGINT NOT NULL REFERENCES academic_periods(id) ON DELETE CASCADE,
    student_id          BIGINT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    student_enrollment_id BIGINT REFERENCES student_enrollments(id) ON DELETE SET NULL,
    criterion_id        BIGINT NOT NULL REFERENCES criteria(id) ON DELETE RESTRICT,
    grade_at_result     SMALLINT NOT NULL,
    grade_track         grade_track_type NOT NULL DEFAULT 'regular',
    base_score          NUMERIC(12,4) NOT NULL,
    dynamic_bonus       NUMERIC(12,4) NOT NULL DEFAULT 0,
    total_score         NUMERIC(12,4) GENERATED ALWAYS AS (base_score + dynamic_bonus) STORED,
    raw_result_value    VARCHAR(100),
    result_date         DATE,
    source_type         VARCHAR(50),
    comment             TEXT,
    created_by_user_id  BIGINT REFERENCES users(id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT student_results_grade_chk CHECK (grade_at_result BETWEEN 2 AND 11),
    CONSTRAINT student_results_base_score_chk CHECK (base_score >= 0),
    CONSTRAINT student_results_dynamic_bonus_chk CHECK (dynamic_bonus >= 0)
);

CREATE INDEX IF NOT EXISTS idx_student_results_student ON student_results(student_id);
CREATE INDEX IF NOT EXISTS idx_student_results_period ON student_results(academic_period_id);
CREATE INDEX IF NOT EXISTS idx_student_results_criterion ON student_results(criterion_id);
CREATE INDEX IF NOT EXISTS idx_student_results_grade ON student_results(grade_at_result, grade_track);
CREATE INDEX IF NOT EXISTS idx_student_results_result_date ON student_results(result_date);

CREATE TABLE IF NOT EXISTS student_result_teacher_links (
    id                  BIGSERIAL PRIMARY KEY,
    student_result_id   BIGINT NOT NULL REFERENCES student_results(id) ON DELETE CASCADE,
    teacher_id          BIGINT NOT NULL REFERENCES teachers(id) ON DELETE RESTRICT,
    share_percent       NUMERIC(5,2) NOT NULL DEFAULT 100.00,
    score_assigned      NUMERIC(12,4) NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT student_result_teacher_links_share_chk CHECK (share_percent > 0 AND share_percent <= 100),
    CONSTRAINT student_result_teacher_links_score_chk CHECK (score_assigned >= 0),
    CONSTRAINT student_result_teacher_links_uniq UNIQUE (student_result_id, teacher_id)
);

CREATE INDEX IF NOT EXISTS idx_student_result_teacher_links_result ON student_result_teacher_links(student_result_id);
CREATE INDEX IF NOT EXISTS idx_student_result_teacher_links_teacher ON student_result_teacher_links(teacher_id);

CREATE TABLE IF NOT EXISTS calculation_settings (
    id                  BIGSERIAL PRIMARY KEY,
    academic_period_id  BIGINT NOT NULL REFERENCES academic_periods(id) ON DELETE CASCADE,
    total_fund          NUMERIC(14,2) NOT NULL,
    total_points_sum    NUMERIC(14,4),
    dismissed_fund      NUMERIC(14,2) NOT NULL DEFAULT 0,
    uvsotr_value        NUMERIC(14,6),
    avg_group_size      NUMERIC(12,4),
    normalization_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    reverse_weight_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    comment             TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT calculation_settings_total_fund_chk CHECK (total_fund >= 0),
    CONSTRAINT calculation_settings_total_points_sum_chk CHECK (total_points_sum IS NULL OR total_points_sum >= 0),
    CONSTRAINT calculation_settings_dismissed_fund_chk CHECK (dismissed_fund >= 0),
    CONSTRAINT calculation_settings_uvsotr_chk CHECK (uvsotr_value IS NULL OR uvsotr_value >= 0),
    CONSTRAINT calculation_settings_avg_group_size_chk CHECK (avg_group_size IS NULL OR avg_group_size >= 0),
    CONSTRAINT calculation_settings_period_uniq UNIQUE (academic_period_id)
);

CREATE TABLE IF NOT EXISTS teacher_calculations (
    id                  BIGSERIAL PRIMARY KEY,
    academic_period_id  BIGINT NOT NULL REFERENCES academic_periods(id) ON DELETE CASCADE,
    teacher_id          BIGINT NOT NULL REFERENCES teachers(id) ON DELETE RESTRICT,
    raw_points          NUMERIC(14,4) NOT NULL DEFAULT 0,
    normalized_points   NUMERIC(14,4),
    reverse_weight      NUMERIC(18,10),
    employee_share      NUMERIC(18,10),
    uvsotr_amount       NUMERIC(14,4),
    final_amount        NUMERIC(14,2) NOT NULL DEFAULT 0,
    student_count_with_results INTEGER,
    total_student_count INTEGER,
    avg_group_ratio     NUMERIC(14,6),
    is_dismissed_snapshot BOOLEAN NOT NULL DEFAULT FALSE,
    calculated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT teacher_calculations_raw_points_chk CHECK (raw_points >= 0),
    CONSTRAINT teacher_calculations_normalized_points_chk CHECK (normalized_points IS NULL OR normalized_points >= 0),
    CONSTRAINT teacher_calculations_reverse_weight_chk CHECK (reverse_weight IS NULL OR reverse_weight >= 0),
    CONSTRAINT teacher_calculations_employee_share_chk CHECK (employee_share IS NULL OR employee_share >= 0),
    CONSTRAINT teacher_calculations_uvsotr_amount_chk CHECK (uvsotr_amount IS NULL OR uvsotr_amount >= 0),
    CONSTRAINT teacher_calculations_final_amount_chk CHECK (final_amount >= 0),
    CONSTRAINT teacher_calculations_student_count_chk CHECK (
        (student_count_with_results IS NULL OR student_count_with_results >= 0) AND
        (total_student_count IS NULL OR total_student_count >= 0)
    ),
    CONSTRAINT teacher_calculations_period_teacher_uniq UNIQUE (academic_period_id, teacher_id)
);

CREATE INDEX IF NOT EXISTS idx_teacher_calculations_period ON teacher_calculations(academic_period_id);
CREATE INDEX IF NOT EXISTS idx_teacher_calculations_teacher ON teacher_calculations(teacher_id);
CREATE INDEX IF NOT EXISTS idx_teacher_calculations_final_amount ON teacher_calculations(final_amount DESC);

CREATE TABLE IF NOT EXISTS teacher_calculation_items (
    id                  BIGSERIAL PRIMARY KEY,
    teacher_calculation_id BIGINT NOT NULL REFERENCES teacher_calculations(id) ON DELETE CASCADE,
    student_result_id   BIGINT NOT NULL REFERENCES student_results(id) ON DELETE CASCADE,
    student_id          BIGINT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    base_points         NUMERIC(12,4) NOT NULL,
    normalized_points   NUMERIC(12,4),
    applied_share_percent NUMERIC(5,2) NOT NULL DEFAULT 100.00,
    final_points_to_teacher NUMERIC(12,4) NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT teacher_calculation_items_base_points_chk CHECK (base_points >= 0),
    CONSTRAINT teacher_calculation_items_normalized_points_chk CHECK (normalized_points IS NULL OR normalized_points >= 0),
    CONSTRAINT teacher_calculation_items_share_chk CHECK (applied_share_percent > 0 AND applied_share_percent <= 100),
    CONSTRAINT teacher_calculation_items_final_points_chk CHECK (final_points_to_teacher >= 0),
    CONSTRAINT teacher_calculation_items_uniq UNIQUE (teacher_calculation_id, student_result_id)
);

CREATE INDEX IF NOT EXISTS idx_teacher_calculation_items_calc ON teacher_calculation_items(teacher_calculation_id);
CREATE INDEX IF NOT EXISTS idx_teacher_calculation_items_result ON teacher_calculation_items(student_result_id);
CREATE INDEX IF NOT EXISTS idx_teacher_calculation_items_student ON teacher_calculation_items(student_id);

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_academic_periods_updated_at ON academic_periods;
CREATE TRIGGER trg_academic_periods_updated_at BEFORE UPDATE ON academic_periods FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_students_updated_at ON students;
CREATE TRIGGER trg_students_updated_at BEFORE UPDATE ON students FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_teachers_updated_at ON teachers;
CREATE TRIGGER trg_teachers_updated_at BEFORE UPDATE ON teachers FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_student_enrollments_updated_at ON student_enrollments;
CREATE TRIGGER trg_student_enrollments_updated_at BEFORE UPDATE ON student_enrollments FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_criterion_groups_updated_at ON criterion_groups;
CREATE TRIGGER trg_criterion_groups_updated_at BEFORE UPDATE ON criterion_groups FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_criteria_updated_at ON criteria;
CREATE TRIGGER trg_criteria_updated_at BEFORE UPDATE ON criteria FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_criterion_grade_weights_updated_at ON criterion_grade_weights;
CREATE TRIGGER trg_criterion_grade_weights_updated_at BEFORE UPDATE ON criterion_grade_weights FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_student_teacher_assignments_updated_at ON student_teacher_assignments;
CREATE TRIGGER trg_student_teacher_assignments_updated_at BEFORE UPDATE ON student_teacher_assignments FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_student_results_updated_at ON student_results;
CREATE TRIGGER trg_student_results_updated_at BEFORE UPDATE ON student_results FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_student_result_teacher_links_updated_at ON student_result_teacher_links;
CREATE TRIGGER trg_student_result_teacher_links_updated_at BEFORE UPDATE ON student_result_teacher_links FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_calculation_settings_updated_at ON calculation_settings;
CREATE TRIGGER trg_calculation_settings_updated_at BEFORE UPDATE ON calculation_settings FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_teacher_calculations_updated_at ON teacher_calculations;
CREATE TRIGGER trg_teacher_calculations_updated_at BEFORE UPDATE ON teacher_calculations FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_teacher_calculation_items_updated_at ON teacher_calculation_items;
CREATE TRIGGER trg_teacher_calculation_items_updated_at BEFORE UPDATE ON teacher_calculation_items FOR EACH ROW EXECUTE FUNCTION set_updated_at();

INSERT INTO academic_periods (name, date_start, date_end, is_closed)
VALUES ('2024–2026', DATE '2024-09-01', DATE '2026-08-31', FALSE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO criterion_groups (code, name, description, sort_order)
VALUES
    ('oge', 'ОГЭ', 'Критерии ОГЭ из листа "Критерии"', 10),
    ('ege', 'ЕГЭ', 'Критерии ЕГЭ по диапазонам баллов из листа "Критерии"', 20),
    ('diagnostics', 'Диагностика', 'Диагностические работы по уровням из листа "Критерии"', 30)
ON CONFLICT (code) DO UPDATE
SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    sort_order = EXCLUDED.sort_order;

INSERT INTO criteria (
    criterion_group_id, code, name, raw_value_label, base_score, max_dynamic_bonus, is_active, sort_order
)
SELECT cg.id, x.code, x.name, x.raw_value_label, x.base_score, NULL, TRUE, x.sort_order
FROM (
    VALUES
        ('oge', 'oge_5', 'ОГЭ (5)', '5', 8.0000, 10),
        ('oge', 'oge_4', 'ОГЭ (4)', '4', 6.0000, 20),
        ('oge', 'oge_3', 'ОГЭ (3)', '3', 4.0000, 30),
        ('ege', 'ege_90_100', 'ЕГЭ 90–100', '90–100', 10.0000, 110),
        ('ege', 'ege_80_89', 'ЕГЭ 80–89', '80–89', 7.0000, 120),
        ('ege', 'ege_70_79', 'ЕГЭ 70–79', '70–79', 5.0000, 130),
        ('ege', 'ege_60_69', 'ЕГЭ 60–69', '60–69', 3.0000, 140),
        ('ege', 'ege_50_59', 'ЕГЭ 50–59', '50–59', 1.0000, 150),
        ('diagnostics', 'diag_10_high', 'Диагностика 10 (Высокий)', 'Высокий', 8.0000, 210),
        ('diagnostics', 'diag_10_advanced', 'Диагностика 10 (Повышенный)', 'Повышенный', 6.0000, 220),
        ('diagnostics', 'diag_10_basic', 'Диагностика 10 (Базовый)', 'Базовый', 4.0000, 230),
        ('diagnostics', 'diag_8_high', 'Диагностика 8 (Высокий)', 'Высокий', 8.0000, 310),
        ('diagnostics', 'diag_8_advanced', 'Диагностика 8 (Повышенный)', 'Повышенный', 6.0000, 320),
        ('diagnostics', 'diag_8_basic', 'Диагностика 8 (Базовый)', 'Базовый', 4.0000, 330),
        ('diagnostics', 'diag_7_high', 'Диагностика 7 (Высокий)', 'Высокий', 8.0000, 410),
        ('diagnostics', 'diag_7_advanced', 'Диагностика 7 (Повышенный)', 'Повышенный', 6.0000, 420),
        ('diagnostics', 'diag_7_basic', 'Диагностика 7 (Базовый)', 'Базовый', 4.0000, 430),
        ('diagnostics', 'diag_6_high', 'Диагностика 6 (Высокий)', 'Высокий', 8.0000, 510),
        ('diagnostics', 'diag_6_advanced', 'Диагностика 6 (Повышенный)', 'Повышенный', 6.0000, 520),
        ('diagnostics', 'diag_6_basic', 'Диагностика 6 (Базовый)', 'Базовый', 4.0000, 530),
        ('diagnostics', 'diag_5_high', 'Диагностика 5 (Высокий)', 'Высокий', 8.0000, 610),
        ('diagnostics', 'diag_5_advanced', 'Диагностика 5 (Повышенный)', 'Повышенный', 6.0000, 620),
        ('diagnostics', 'diag_5_basic', 'Диагностика 5 (Базовый)', 'Базовый', 4.0000, 630),
        ('diagnostics', 'diag_4_high', 'Диагностика 4 (Высокий)', 'Высокий', 8.0000, 710),
        ('diagnostics', 'diag_4_advanced', 'Диагностика 4 (Повышенный)', 'Повышенный', 6.0000, 720),
        ('diagnostics', 'diag_4_basic', 'Диагностика 4 (Базовый)', 'Базовый', 4.0000, 730)
) AS x(group_code, code, name, raw_value_label, base_score, sort_order)
JOIN criterion_groups cg ON cg.code = x.group_code
ON CONFLICT (code) DO UPDATE
SET
    criterion_group_id = EXCLUDED.criterion_group_id,
    name = EXCLUDED.name,
    raw_value_label = EXCLUDED.raw_value_label,
    base_score = EXCLUDED.base_score,
    is_active = EXCLUDED.is_active,
    sort_order = EXCLUDED.sort_order;

INSERT INTO criterion_grade_weights (criterion_id, grade, grade_track, weight_value)
SELECT c.id, v.grade, v.grade_track::grade_track_type, v.weight_value
FROM criteria c
JOIN (
    VALUES
        ('oge_5', 2, 'regular', 0.160000), ('oge_5', 3, 'regular', 0.240000), ('oge_5', 4, 'regular', 0.400000), ('oge_5', 5, 'regular', 0.800000), ('oge_5', 6, 'regular', 1.200000), ('oge_5', 7, 'regular', 1.600000), ('oge_5', 8, 'regular', 1.600000), ('oge_5', 9, 'regular', 2.000000),
        ('oge_4', 2, 'regular', 0.120000), ('oge_4', 3, 'regular', 0.180000), ('oge_4', 4, 'regular', 0.300000), ('oge_4', 5, 'regular', 0.600000), ('oge_4', 6, 'regular', 0.900000), ('oge_4', 7, 'regular', 1.200000), ('oge_4', 8, 'regular', 1.200000), ('oge_4', 9, 'regular', 1.500000),
        ('oge_3', 2, 'regular', 0.080000), ('oge_3', 3, 'regular', 0.120000), ('oge_3', 4, 'regular', 0.200000), ('oge_3', 5, 'regular', 0.400000), ('oge_3', 6, 'regular', 0.600000), ('oge_3', 7, 'regular', 0.800000), ('oge_3', 8, 'regular', 0.800000), ('oge_3', 9, 'regular', 1.000000),
        ('ege_90_100', 2, 'regular', 0.100000), ('ege_90_100', 3, 'regular', 0.100000), ('ege_90_100', 4, 'regular', 0.200000), ('ege_90_100', 5, 'regular', 0.400000), ('ege_90_100', 6, 'regular', 0.600000), ('ege_90_100', 7, 'regular', 0.800000), ('ege_90_100', 8, 'regular', 1.000000), ('ege_90_100', 9, 'regular', 1.000000), ('ege_90_100', 10, 'regular', 1.000000), ('ege_90_100', 11, 'course', 2.400000), ('ege_90_100', 11, 'practicum', 2.400000),
        ('ege_80_89', 2, 'regular', 0.070000), ('ege_80_89', 3, 'regular', 0.070000), ('ege_80_89', 4, 'regular', 0.140000), ('ege_80_89', 5, 'regular', 0.280000), ('ege_80_89', 6, 'regular', 0.420000), ('ege_80_89', 7, 'regular', 0.560000), ('ege_80_89', 8, 'regular', 0.700000), ('ege_80_89', 9, 'regular', 0.700000), ('ege_80_89', 10, 'regular', 0.700000), ('ege_80_89', 11, 'course', 1.680000), ('ege_80_89', 11, 'practicum', 1.680000),
        ('ege_70_79', 2, 'regular', 0.050000), ('ege_70_79', 3, 'regular', 0.050000), ('ege_70_79', 4, 'regular', 0.100000), ('ege_70_79', 5, 'regular', 0.200000), ('ege_70_79', 6, 'regular', 0.300000), ('ege_70_79', 7, 'regular', 0.400000), ('ege_70_79', 8, 'regular', 0.500000), ('ege_70_79', 9, 'regular', 0.500000), ('ege_70_79', 10, 'regular', 0.500000), ('ege_70_79', 11, 'course', 1.200000), ('ege_70_79', 11, 'practicum', 1.200000),
        ('ege_60_69', 2, 'regular', 0.030000), ('ege_60_69', 3, 'regular', 0.030000), ('ege_60_69', 4, 'regular', 0.060000), ('ege_60_69', 5, 'regular', 0.120000), ('ege_60_69', 6, 'regular', 0.180000), ('ege_60_69', 7, 'regular', 0.240000), ('ege_60_69', 8, 'regular', 0.300000), ('ege_60_69', 9, 'regular', 0.300000), ('ege_60_69', 10, 'regular', 0.300000), ('ege_60_69', 11, 'course', 0.720000), ('ege_60_69', 11, 'practicum', 0.720000),
        ('ege_50_59', 2, 'regular', 0.010000), ('ege_50_59', 3, 'regular', 0.010000), ('ege_50_59', 4, 'regular', 0.020000), ('ege_50_59', 5, 'regular', 0.040000), ('ege_50_59', 6, 'regular', 0.060000), ('ege_50_59', 7, 'regular', 0.080000), ('ege_50_59', 8, 'regular', 0.100000), ('ege_50_59', 9, 'regular', 0.100000), ('ege_50_59', 10, 'regular', 0.100000), ('ege_50_59', 11, 'course', 0.240000), ('ege_50_59', 11, 'practicum', 0.240000),
        ('diag_10_high', 2, 'regular', 0.080000), ('diag_10_high', 3, 'regular', 0.080000), ('diag_10_high', 4, 'regular', 0.160000), ('diag_10_high', 5, 'regular', 0.320000), ('diag_10_high', 6, 'regular', 0.480000), ('diag_10_high', 7, 'regular', 0.800000), ('diag_10_high', 8, 'regular', 1.600000), ('diag_10_high', 9, 'regular', 1.600000), ('diag_10_high', 10, 'regular', 2.880000),
        ('diag_10_advanced', 2, 'regular', 0.060000), ('diag_10_advanced', 3, 'regular', 0.060000), ('diag_10_advanced', 4, 'regular', 0.120000), ('diag_10_advanced', 5, 'regular', 0.240000), ('diag_10_advanced', 6, 'regular', 0.360000), ('diag_10_advanced', 7, 'regular', 0.600000), ('diag_10_advanced', 8, 'regular', 1.200000), ('diag_10_advanced', 9, 'regular', 1.200000), ('diag_10_advanced', 10, 'regular', 2.160000),
        ('diag_10_basic', 2, 'regular', 0.400000), ('diag_10_basic', 3, 'regular', 0.400000), ('diag_10_basic', 4, 'regular', 0.800000), ('diag_10_basic', 5, 'regular', 1.600000), ('diag_10_basic', 6, 'regular', 2.400000), ('diag_10_basic', 7, 'regular', 3.200000), ('diag_10_basic', 8, 'regular', 4.000000), ('diag_10_basic', 9, 'regular', 4.000000), ('diag_10_basic', 10, 'regular', 4.000000),
        ('diag_8_high', 2, 'regular', 0.800000), ('diag_8_high', 3, 'regular', 0.800000), ('diag_8_high', 4, 'regular', 0.800000), ('diag_8_high', 5, 'regular', 0.800000), ('diag_8_high', 6, 'regular', 0.800000), ('diag_8_high', 7, 'regular', 1.600000), ('diag_8_high', 8, 'regular', 2.400000),
        ('diag_8_advanced', 2, 'regular', 0.600000), ('diag_8_advanced', 3, 'regular', 0.600000), ('diag_8_advanced', 4, 'regular', 0.600000), ('diag_8_advanced', 5, 'regular', 0.600000), ('diag_8_advanced', 6, 'regular', 0.600000), ('diag_8_advanced', 7, 'regular', 1.200000), ('diag_8_advanced', 8, 'regular', 1.800000),
        ('diag_8_basic', 2, 'regular', 0.400000), ('diag_8_basic', 3, 'regular', 0.400000), ('diag_8_basic', 4, 'regular', 0.400000), ('diag_8_basic', 5, 'regular', 0.400000), ('diag_8_basic', 6, 'regular', 0.400000), ('diag_8_basic', 7, 'regular', 0.800000), ('diag_8_basic', 8, 'regular', 1.200000),
        ('diag_7_high', 2, 'regular', 0.800000), ('diag_7_high', 3, 'regular', 0.800000), ('diag_7_high', 4, 'regular', 0.800000), ('diag_7_high', 5, 'regular', 1.600000), ('diag_7_high', 6, 'regular', 1.600000), ('diag_7_high', 7, 'regular', 2.400000),
        ('diag_7_advanced', 2, 'regular', 0.600000), ('diag_7_advanced', 3, 'regular', 0.600000), ('diag_7_advanced', 4, 'regular', 0.600000), ('diag_7_advanced', 5, 'regular', 1.200000), ('diag_7_advanced', 6, 'regular', 1.200000), ('diag_7_advanced', 7, 'regular', 1.800000),
        ('diag_7_basic', 2, 'regular', 0.400000), ('diag_7_basic', 3, 'regular', 0.400000), ('diag_7_basic', 4, 'regular', 0.400000), ('diag_7_basic', 5, 'regular', 0.800000), ('diag_7_basic', 6, 'regular', 0.800000), ('diag_7_basic', 7, 'regular', 1.200000),
        ('diag_6_high', 2, 'regular', 0.800000), ('diag_6_high', 3, 'regular', 0.800000), ('diag_6_high', 4, 'regular', 1.600000), ('diag_6_high', 5, 'regular', 1.600000), ('diag_6_high', 6, 'regular', 3.200000),
        ('diag_6_advanced', 2, 'regular', 0.600000), ('diag_6_advanced', 3, 'regular', 0.600000), ('diag_6_advanced', 4, 'regular', 1.200000), ('diag_6_advanced', 5, 'regular', 1.200000), ('diag_6_advanced', 6, 'regular', 2.400000),
        ('diag_6_basic', 2, 'regular', 0.400000), ('diag_6_basic', 3, 'regular', 0.400000), ('diag_6_basic', 4, 'regular', 0.800000), ('diag_6_basic', 5, 'regular', 0.800000), ('diag_6_basic', 6, 'regular', 1.600000),
        ('diag_5_high', 2, 'regular', 1.600000), ('diag_5_high', 3, 'regular', 1.600000), ('diag_5_high', 4, 'regular', 1.600000), ('diag_5_high', 5, 'regular', 3.200000),
        ('diag_5_advanced', 2, 'regular', 1.200000), ('diag_5_advanced', 3, 'regular', 1.200000), ('diag_5_advanced', 4, 'regular', 1.200000), ('diag_5_advanced', 5, 'regular', 2.400000),
        ('diag_5_basic', 2, 'regular', 0.800000), ('diag_5_basic', 3, 'regular', 0.800000), ('diag_5_basic', 4, 'regular', 0.800000), ('diag_5_basic', 5, 'regular', 1.600000),
        ('diag_4_high', 2, 'regular', 2.000000), ('diag_4_high', 3, 'regular', 2.000000), ('diag_4_high', 4, 'regular', 4.000000),
        ('diag_4_advanced', 2, 'regular', 1.500000), ('diag_4_advanced', 3, 'regular', 1.500000), ('diag_4_advanced', 4, 'regular', 3.000000),
        ('diag_4_basic', 2, 'regular', 1.000000), ('diag_4_basic', 3, 'regular', 1.000000), ('diag_4_basic', 4, 'regular', 2.000000)
) AS v(code, grade, grade_track, weight_value)
    ON c.code = v.code
ON CONFLICT (criterion_id, grade, grade_track) DO UPDATE
SET weight_value = EXCLUDED.weight_value;

INSERT INTO calculation_settings (
    academic_period_id, total_fund, total_points_sum, dismissed_fund, uvsotr_value, avg_group_size,
    normalization_enabled, reverse_weight_enabled, comment
)
SELECT ap.id, 1445.00, 1506.0000, 458.06, 30.537000, 73.0000, TRUE, TRUE,
       'Первичные настройки импортированы по листам ОБЩАЯ и Выравнивание баллов'
FROM academic_periods ap
WHERE ap.name = '2024–2026'
ON CONFLICT (academic_period_id) DO UPDATE
SET total_fund = EXCLUDED.total_fund,
    total_points_sum = EXCLUDED.total_points_sum,
    dismissed_fund = EXCLUDED.dismissed_fund,
    uvsotr_value = EXCLUDED.uvsotr_value,
    avg_group_size = EXCLUDED.avg_group_size,
    normalization_enabled = EXCLUDED.normalization_enabled,
    reverse_weight_enabled = EXCLUDED.reverse_weight_enabled,
    comment = EXCLUDED.comment;

DROP TABLE IF EXISTS stg_student_results;
CREATE TEMP TABLE stg_student_results (
    student_name         TEXT NOT NULL,
    criterion_name       TEXT NOT NULL,
    base_score           NUMERIC(12,4) NOT NULL,
    dynamic_bonus        NUMERIC(12,4),
    total_score          NUMERIC(12,4)
);

INSERT INTO stg_student_results (student_name, criterion_name, base_score, dynamic_bonus, total_score) VALUES
    ('Бегалиева Милиена', 'ЕГЭ 80–89', 10.0000, 1.0000, 11.0000),
    ('Вигилянский Валерий', 'ЕГЭ 70–79', 8.0000, 0.0000, 8.0000),
    ('Гревцова Мария', 'ЕГЭ 90–100', 12.0000, 4.0000, 16.0000),
    ('Калиновский Никита', 'ЕГЭ 50–59', 4.0000, 4.0000, 8.0000),
    ('Мерзляков Дмитрий', 'ЕГЭ 60–69', 6.0000, 4.0000, 10.0000),
    ('Нагашян Эрик', 'ЕГЭ 80–89', 10.0000, 1.0000, 11.0000),
    ('Смышляева Дарья', 'ЕГЭ 90–100', 12.0000, 2.0000, 14.0000),
    ('Хакина Яна', 'ЕГЭ 50–59', 4.0000, 2.0000, 6.0000),
    ('Хачатурян Савелий', 'ЕГЭ 60–69', 6.0000, 2.0000, 8.0000),
    ('Юрьева Анна', 'ЕГЭ 50–59', 4.0000, 3.0000, 7.0000),
    ('Бубнов Ярослав', 'ЕГЭ 80–89', 10.0000, 2.0000, 12.0000),
    ('Галибина Кира', 'ЕГЭ 60–69', 6.0000, 0.0000, 6.0000),
    ('Гулакова Ксения', 'ЕГЭ 50–59', 4.0000, 0.0000, 4.0000),
    ('Гусев Ярослав', 'ЕГЭ 70–79', 8.0000, 0.0000, 8.0000);

DROP TABLE IF EXISTS stg_student_teacher_matrix;
CREATE TEMP TABLE stg_student_teacher_matrix (
    student_name         TEXT NOT NULL,
    grade                SMALLINT NOT NULL,
    grade_track          grade_track_type NOT NULL,
    teacher_name         TEXT NOT NULL
);

INSERT INTO stg_student_teacher_matrix (student_name, grade, grade_track, teacher_name) VALUES
    ('Бегалиева Милиена', 10, 'regular', 'Коржакова'), ('Бегалиева Милиена', 11, 'course', 'Коржакова'), ('Бегалиева Милиена', 11, 'practicum', 'Коржакова'),
    ('Вигилянский Валерий', 11, 'course', 'Данилин'), ('Вигилянский Валерий', 11, 'practicum', 'Данилин'),
    ('Гревцова Мария', 10, 'regular', 'Коржакова'), ('Гревцова Мария', 11, 'course', 'Коржакова'), ('Гревцова Мария', 11, 'practicum', 'Коржакова'),
    ('Калиновский Никита', 2, 'regular', 'Уволившиеся'), ('Калиновский Никита', 3, 'regular', 'Уволившиеся'), ('Калиновский Никита', 4, 'regular', 'Уволившиеся'), ('Калиновский Никита', 5, 'regular', 'Уволившиеся'), ('Калиновский Никита', 6, 'regular', 'Уволившиеся'), ('Калиновский Никита', 7, 'regular', 'Уволившиеся'), ('Калиновский Никита', 8, 'regular', 'Уволившиеся'), ('Калиновский Никита', 9, 'regular', 'Уволившиеся'), ('Калиновский Никита', 10, 'regular', 'Уволившиеся'), ('Калиновский Никита', 11, 'course', 'Уволившиеся'), ('Калиновский Никита', 11, 'practicum', 'Уволившиеся'),
    ('Мерзляков Дмитрий', 2, 'regular', 'Гришакова'), ('Мерзляков Дмитрий', 3, 'regular', 'Гришакова'), ('Мерзляков Дмитрий', 4, 'regular', 'Гришакова'), ('Мерзляков Дмитрий', 5, 'regular', 'Гришакова'), ('Мерзляков Дмитрий', 6, 'regular', 'Гришакова'), ('Мерзляков Дмитрий', 7, 'regular', 'Сапронова'), ('Мерзляков Дмитрий', 8, 'regular', 'Сапронова'), ('Мерзляков Дмитрий', 9, 'regular', 'Сапронова'), ('Мерзляков Дмитрий', 10, 'regular', 'Власова'), ('Мерзляков Дмитрий', 11, 'course', 'Власова'), ('Мерзляков Дмитрий', 11, 'practicum', 'Коржакова'),
    ('Нагашян Эрик', 6, 'regular', 'Саликова'), ('Нагашян Эрик', 7, 'regular', 'Саликова'), ('Нагашян Эрик', 8, 'regular', 'Саликова'), ('Нагашян Эрик', 9, 'regular', 'Саликова'), ('Нагашян Эрик', 10, 'regular', 'Коржакова'), ('Нагашян Эрик', 11, 'course', 'Коржакова'), ('Нагашян Эрик', 11, 'practicum', 'Коржакова'),
    ('Смышляева Дарья', 5, 'regular', 'Коржакова'), ('Смышляева Дарья', 6, 'regular', 'Коржакова'), ('Смышляева Дарья', 7, 'regular', 'Коржакова'), ('Смышляева Дарья', 8, 'regular', 'Коржакова'), ('Смышляева Дарья', 9, 'regular', 'Коржакова'), ('Смышляева Дарья', 10, 'regular', 'Коржакова'), ('Смышляева Дарья', 11, 'course', 'Коржакова'), ('Смышляева Дарья', 11, 'practicum', 'Коржакова'),
    ('Хакина Яна', 9, 'regular', 'Абрамова'),
    ('Хачатурян Савелий', 10, 'regular', 'Власова'),
    ('Юрьева Анна', 5, 'regular', 'Коржакова'), ('Юрьева Анна', 6, 'regular', 'Коржакова'), ('Юрьева Анна', 7, 'regular', 'Коржакова'), ('Юрьева Анна', 8, 'regular', 'Коржакова'), ('Юрьева Анна', 9, 'regular', 'Коржакова'),
    ('Бубнов Ярослав', 9, 'regular', 'Данилин'), ('Бубнов Ярослав', 10, 'regular', 'Коржакова'), ('Бубнов Ярослав', 11, 'course', 'Коржакова'), ('Бубнов Ярослав', 11, 'practicum', 'Коржакова'),
    ('Галибина Кира', 2, 'regular', 'Имаметдинова'), ('Галибина Кира', 3, 'regular', 'Имаметдинова'), ('Галибина Кира', 4, 'regular', 'Имаметдинова'), ('Галибина Кира', 5, 'regular', 'Имаметдинова'), ('Галибина Кира', 6, 'regular', 'Имаметдинова'), ('Галибина Кира', 9, 'regular', 'Власова'), ('Галибина Кира', 10, 'regular', 'Коржакова'), ('Галибина Кира', 11, 'course', 'Коржакова'), ('Галибина Кира', 11, 'practicum', 'Данилин'),
    ('Гулакова Ксения', 10, 'regular', 'Данилин'), ('Гулакова Ксения', 11, 'course', 'Данилин'), ('Гулакова Ксения', 11, 'practicum', 'Данилин'),
    ('Гусев Ярослав', 7, 'regular', 'Кирьянова'), ('Гусев Ярослав', 10, 'regular', 'Данилин'), ('Гусев Ярослав', 11, 'course', 'Данилин'), ('Гусев Ярослав', 11, 'practicum', 'Коржакова');

INSERT INTO teachers (full_name, short_name, is_dismissed, dismissed_at)
VALUES
    ('Абрамова А.А.', 'Абрамова', FALSE, NULL),
    ('Власова Е.А.', 'Власова', FALSE, NULL),
    ('Гришакова Е.А.', 'Гришакова', FALSE, NULL),
    ('Данилин М.В.', 'Данилин', FALSE, NULL),
    ('Дудорова Н.И.', 'Дудорова', FALSE, NULL),
    ('Имаметдинова А.М.', 'Имаметдинова', FALSE, NULL),
    ('Кирьянова Т.А.', 'Кирьянова', FALSE, NULL),
    ('Коржакова О.В.', 'Коржакова', FALSE, NULL),
    ('Кузьмичева Т.Д.', 'Кузьмичева', FALSE, NULL),
    ('Курило Т.Г.', 'Курило', FALSE, NULL),
    ('Плющенкова Т.Е.', 'Плющенкова', FALSE, NULL),
    ('Саликова Л.С.', 'Саликова', FALSE, NULL),
    ('Сапронова И.В.', 'Сапронова', FALSE, NULL),
    ('Цыплакова О.И.', 'Цыплакова', FALSE, NULL),
    ('Цэкурас А.А.', 'Цэкурас', FALSE, NULL),
    ('Белых Е.В.', 'Белых', FALSE, NULL),
    ('Уволившиеся', 'Уволившиеся', TRUE, DATE '2024-09-01')
ON CONFLICT DO NOTHING;

INSERT INTO students (full_name)
SELECT DISTINCT s.student_name FROM stg_student_results s
WHERE NOT EXISTS (
    SELECT 1 FROM students st
    WHERE st.full_name_normalized = lower(regexp_replace(btrim(s.student_name), '\s+', ' ', 'g'))
);

INSERT INTO students (full_name)
SELECT DISTINCT m.student_name
FROM stg_student_teacher_matrix m
WHERE NOT EXISTS (
    SELECT 1 FROM students st
    WHERE st.full_name_normalized = lower(regexp_replace(btrim(m.student_name), '\s+', ' ', 'g'))
);

INSERT INTO student_enrollments (student_id, academic_period_id, grade, grade_track, grade_label, class_letter)
SELECT DISTINCT
    st.id,
    ap.id,
    m.grade,
    m.grade_track,
    CASE
        WHEN m.grade = 11 AND m.grade_track = 'course' THEN '11 (уроки)'
        WHEN m.grade = 11 AND m.grade_track = 'practicum' THEN '11 (практикумы)'
        ELSE m.grade::text
    END,
    NULL
FROM stg_student_teacher_matrix m
JOIN students st
  ON st.full_name_normalized = lower(regexp_replace(btrim(m.student_name), '\s+', ' ', 'g'))
JOIN academic_periods ap
  ON ap.name = '2024–2026'
ON CONFLICT (student_id, academic_period_id, grade, grade_track, class_letter) DO NOTHING;

INSERT INTO student_teacher_assignments (
    student_id, teacher_id, academic_period_id, grade, grade_track, assignment_type, share_percent, is_active
)
SELECT
    st.id,
    t.id,
    ap.id,
    m.grade,
    m.grade_track,
    'main'::assignment_type_enum,
    100.00,
    TRUE
FROM stg_student_teacher_matrix m
JOIN students st
  ON st.full_name_normalized = lower(regexp_replace(btrim(m.student_name), '\s+', ' ', 'g'))
JOIN teachers t
  ON lower(regexp_replace(btrim(t.short_name), '\s+', ' ', 'g')) =
     lower(regexp_replace(btrim(m.teacher_name), '\s+', ' ', 'g'))
JOIN academic_periods ap
  ON ap.name = '2024–2026'
ON CONFLICT (student_id, teacher_id, academic_period_id, grade, grade_track, assignment_type) DO NOTHING;

WITH result_grade_pick AS (
    SELECT
        st.id AS student_id,
        ap.id AS academic_period_id,
        COALESCE(
            MAX(se.grade) FILTER (WHERE se.grade = 11 AND se.grade_track = 'course'),
            MAX(se.grade)
        ) AS picked_grade,
        COALESCE(
            MAX(se.grade_track) FILTER (WHERE se.grade = 11 AND se.grade_track = 'course'),
            'regular'::grade_track_type
        ) AS picked_track
    FROM students st
    JOIN academic_periods ap ON ap.name = '2024–2026'
    LEFT JOIN student_enrollments se
      ON se.student_id = st.id
     AND se.academic_period_id = ap.id
    GROUP BY st.id, ap.id
)
INSERT INTO student_results (
    academic_period_id, student_id, student_enrollment_id, criterion_id, grade_at_result, grade_track,
    base_score, dynamic_bonus, raw_result_value, result_date, source_type, comment
)
SELECT
    ap.id,
    st.id,
    se.id,
    c.id,
    rg.picked_grade,
    rg.picked_track,
    r.base_score,
    COALESCE(r.dynamic_bonus, 0),
    r.criterion_name,
    NULL,
    'excel_import',
    CASE WHEN c.base_score <> r.base_score
         THEN 'Импорт из Excel: base_score в строке Excel не совпадает со справочником criteria'
         ELSE 'Импорт из Excel'
    END
FROM stg_student_results r
JOIN students st
  ON st.full_name_normalized = lower(regexp_replace(btrim(r.student_name), '\s+', ' ', 'g'))
JOIN academic_periods ap ON ap.name = '2024–2026'
JOIN result_grade_pick rg ON rg.student_id = st.id AND rg.academic_period_id = ap.id
LEFT JOIN student_enrollments se
  ON se.student_id = st.id
 AND se.academic_period_id = ap.id
 AND se.grade = rg.picked_grade
 AND se.grade_track = rg.picked_track
JOIN criteria c ON c.name = r.criterion_name;

CREATE OR REPLACE VIEW v_teacher_stim_summary AS
WITH teacher_student_scope AS (
    SELECT sta.academic_period_id, sta.teacher_id, sta.student_id, sta.grade, sta.grade_track, sta.share_percent
    FROM student_teacher_assignments sta
    WHERE sta.is_active = TRUE
),
teacher_result_points AS (
    SELECT
        ts.academic_period_id,
        ts.teacher_id,
        ts.student_id,
        SUM(sr.total_score * ts.share_percent / 100.0) AS raw_points_by_student
    FROM teacher_student_scope ts
    JOIN student_results sr
      ON sr.academic_period_id = ts.academic_period_id
     AND sr.student_id = ts.student_id
     AND sr.grade_at_result = ts.grade
     AND sr.grade_track = ts.grade_track
    GROUP BY ts.academic_period_id, ts.teacher_id, ts.student_id
),
teacher_base AS (
    SELECT academic_period_id, teacher_id, COUNT(*) AS student_count_with_results, SUM(raw_points_by_student) AS raw_points
    FROM teacher_result_points
    GROUP BY academic_period_id, teacher_id
),
teacher_total_students AS (
    SELECT academic_period_id, teacher_id, COUNT(DISTINCT student_id) AS total_student_count
    FROM teacher_student_scope
    GROUP BY academic_period_id, teacher_id
),
teacher_scope_join AS (
    SELECT
        tts.academic_period_id,
        tts.teacher_id,
        COALESCE(tb.student_count_with_results, 0) AS student_count_with_results,
        tts.total_student_count,
        COALESCE(tb.raw_points, 0) AS raw_points
    FROM teacher_total_students tts
    LEFT JOIN teacher_base tb
      ON tb.academic_period_id = tts.academic_period_id
     AND tb.teacher_id = tts.teacher_id
),
avg_group AS (
    SELECT academic_period_id,
           AVG(student_count_with_results::numeric) FILTER (WHERE student_count_with_results > 0) AS avg_group_size
    FROM teacher_scope_join
    GROUP BY academic_period_id
),
normalized AS (
    SELECT
        tsj.academic_period_id,
        tsj.teacher_id,
        tsj.student_count_with_results,
        tsj.total_student_count,
        tsj.raw_points,
        ag.avg_group_size,
        CASE
            WHEN tsj.student_count_with_results > 0 AND ag.avg_group_size > 0
            THEN ag.avg_group_size / tsj.student_count_with_results::numeric
            ELSE 0
        END AS normalization_factor,
        CASE
            WHEN tsj.student_count_with_results > 0 AND ag.avg_group_size > 0
            THEN tsj.raw_points * (ag.avg_group_size / tsj.student_count_with_results::numeric)
            ELSE 0
        END AS normalized_points
    FROM teacher_scope_join tsj
    LEFT JOIN avg_group ag ON ag.academic_period_id = tsj.academic_period_id
),
shares AS (
    SELECT
        n.*,
        SUM(n.normalized_points) OVER (PARTITION BY n.academic_period_id) AS total_normalized_points,
        CASE WHEN n.raw_points > 0 THEN 1.0 / n.raw_points ELSE 0 END AS reverse_weight
    FROM normalized n
),
reverse_pool AS (
    SELECT s.*, SUM(s.reverse_weight) OVER (PARTITION BY s.academic_period_id) AS total_reverse_weight
    FROM shares s
),
settings AS (
    SELECT
        cs.academic_period_id,
        cs.total_fund,
        cs.dismissed_fund,
        COALESCE(cs.total_fund, 0) - COALESCE(cs.dismissed_fund, 0) AS distributable_fund,
        cs.uvsotr_value
    FROM calculation_settings cs
)
SELECT
    ap.name AS academic_period,
    t.full_name AS teacher_name,
    t.short_name AS teacher_short_name,
    t.is_dismissed,
    rp.student_count_with_results,
    rp.total_student_count,
    rp.avg_group_size,
    rp.raw_points,
    rp.normalization_factor,
    rp.normalized_points,
    CASE WHEN rp.total_normalized_points > 0 THEN rp.normalized_points / rp.total_normalized_points ELSE 0 END AS normalized_share_percent,
    rp.reverse_weight,
    rp.total_reverse_weight,
    CASE WHEN rp.total_reverse_weight > 0 THEN rp.reverse_weight / rp.total_reverse_weight ELSE 0 END AS employee_share,
    s.total_fund,
    s.dismissed_fund,
    s.distributable_fund,
    s.uvsotr_value,
    CASE WHEN s.distributable_fund IS NOT NULL AND rp.total_reverse_weight > 0
         THEN s.distributable_fund * (rp.reverse_weight / rp.total_reverse_weight)
         ELSE NULL END AS reverse_incentive_amount,
    CASE WHEN s.distributable_fund IS NOT NULL AND rp.total_normalized_points > 0
         THEN s.distributable_fund * (rp.normalized_points / rp.total_normalized_points)
         ELSE NULL END AS normalized_fund_amount
FROM reverse_pool rp
JOIN teachers t ON t.id = rp.teacher_id
JOIN academic_periods ap ON ap.id = rp.academic_period_id
LEFT JOIN settings s ON s.academic_period_id = rp.academic_period_id
ORDER BY ap.name, t.full_name;

COMMIT;


-- V2 NOTE: refresh academic period to 2025–2027 and update criteria scores from STIMUL-MO-IIa-POPYTKA-2025-2027.xlsx
