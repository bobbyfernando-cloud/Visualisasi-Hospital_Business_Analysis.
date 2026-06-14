-- Eksplorasi data awal
SELECT * FROM `portofolio-498810.Hospital_analysis.admissions` LIMIT 10;
SELECT * FROM `portofolio-498810.Hospital_analysis.doctors` LIMIT 10;
SELECT * FROM `portofolio-498810.Hospital_analysis.departments` LIMIT 10;
SELECT * FROM `portofolio-498810.Hospital_analysis.branches` LIMIT 10;
SELECT * FROM `portofolio-498810.Hospital_analysis.billing` LIMIT 10;

-- Cek project ID (opsional)
SELECT @@project_id AS project_id;

-- Lihat daftar kolom dan tipe data setiap tabel
SELECT column_name, data_type 
FROM `portofolio-498810.Hospital_analysis.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'admissions'
ORDER BY ordinal_position;

SELECT column_name, data_type 
FROM `portofolio-498810.Hospital_analysis.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'doctors'
ORDER BY ordinal_position;

SELECT column_name, data_type 
FROM `portofolio-498810.Hospital_analysis.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'departments'
ORDER BY ordinal_position;

SELECT column_name, data_type
FROM `portofolio-498810.Hospital_analysis.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'branches'
ORDER BY ordinal_position;

SELECT column_name, data_type
FROM `portofolio-498810.Hospital_analysis.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'billing'
ORDER BY ordinal_position;

-- Query analisis: metrik dasar admissions (diperbaiki)
WITH admission_metrics AS (
  SELECT
    COUNT(*) AS total_admissions,
    COUNT(DISTINCT patient_id) AS unique_patients,
    COUNT(DISTINCT doctor_id) AS active_doctors
  FROM `portofolio-498810.Hospital_analysis.admissions`
)
SELECT * FROM admission_metrics;

-- ============================================================
--  HOSPITAL BUSINESS ANALYSIS — QUERY SQL LENGKAP UNTUK BIGQUERY
--  Dataset : admissions
--  Kolom   : admission_id, patient_id, doctor_id, department_id,
--             branch_id, admission_date, discharge_date,
--             length_of_stay_days, admission_type, diagnosis_group,
--             room_class, referral_source
-- ============================================================

-- ============================================================
--  BAGIAN 1 : RINGKASAN UMUM (KPI Overview)
-- ============================================================

-- 1.1 Metrik utama keseluruhan
SELECT
    COUNT(*)                                          AS total_admisi,
    COUNT(DISTINCT patient_id)                        AS pasien_unik,
    COUNT(DISTINCT doctor_id)                         AS dokter_aktif,
    COUNT(DISTINCT branch_id)                         AS jumlah_cabang,
    COUNT(DISTINCT department_id)                     AS jumlah_departemen,
    ROUND(AVG(length_of_stay_days), 2)                AS rata_rata_los,
    SUM(CASE WHEN admission_type = 'Emergency'
             THEN 1 ELSE 0 END)                       AS total_emergency,
    ROUND(
        SUM(CASE WHEN admission_type = 'Emergency'
                 THEN 1 ELSE 0 END) * 100.0
        / COUNT(*), 2
    )                                                 AS emergency_rate_pct,
    ROUND(COUNT(*) * 1.0
          / COUNT(DISTINCT doctor_id), 2)             AS avg_admisi_per_dokter
FROM `portofolio-498810.Hospital_analysis.admissions`;

-- ============================================================
--  BAGIAN 2 : TREN VOLUME ADMISI
-- ============================================================

-- 2.1 Volume admisi per bulan (semua tahun)
SELECT
    EXTRACT(YEAR FROM admission_date)            AS tahun,
    EXTRACT(MONTH FROM admission_date)           AS bulan,
    FORMAT_DATE('%Y-%m', admission_date)         AS periode,
    COUNT(*)                                     AS total_admisi
FROM `portofolio-498810.Hospital_analysis.admissions`
GROUP BY tahun, bulan, periode
ORDER BY tahun, bulan;

-- 2.2 Perbandingan volume 2024 vs 2025
SELECT
    EXTRACT(YEAR FROM admission_date)    AS tahun,
    COUNT(*)                             AS total_admisi,
    ROUND(AVG(length_of_stay_days), 2)   AS avg_los,
    SUM(CASE WHEN admission_type = 'Emergency' THEN 1 ELSE 0 END) AS emergency,
    SUM(CASE WHEN referral_source = 'Digital Appointment' THEN 1 ELSE 0 END) AS digital_booking
FROM `portofolio-498810.Hospital_analysis.admissions`
GROUP BY tahun
ORDER BY tahun;

-- 2.3 Pertumbuhan admisi bulan-ke-bulan (MoM) — pakai window function
WITH monthly AS (
    SELECT
        FORMAT_DATE('%Y-%m', admission_date) AS periode,
        COUNT(*) AS total_admisi
    FROM `portofolio-498810.Hospital_analysis.admissions`
    GROUP BY periode
)
SELECT
    periode,
    total_admisi,
    LAG(total_admisi) OVER (ORDER BY periode)   AS admisi_bulan_lalu,
    total_admisi - LAG(total_admisi) OVER (ORDER BY periode) AS selisih,
    ROUND(
        (total_admisi - LAG(total_admisi) OVER (ORDER BY periode))
        * 100.0
        / NULLIF(LAG(total_admisi) OVER (ORDER BY periode), 0)
    , 1)                                         AS growth_mom_pct
FROM monthly
ORDER BY periode;

-- ============================================================
--  BAGIAN 3 : TIPE ADMISI & SUMBER RUJUKAN
-- ============================================================

-- 3.1 Distribusi tipe admisi
SELECT
    admission_type,
    COUNT(*)                                    AS total,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS persen
FROM `portofolio-498810.Hospital_analysis.admissions`
GROUP BY admission_type
ORDER BY total DESC;

-- 3.2 Distribusi sumber rujukan
SELECT
    referral_source,
    COUNT(*)                                    AS total,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS persen
FROM `portofolio-498810.Hospital_analysis.admissions`
GROUP BY referral_source
ORDER BY total DESC;

-- 3.3 Matriks silang: sumber rujukan × tipe admisi
SELECT
    referral_source,
    SUM(CASE WHEN admission_type = 'Walk-in'   THEN 1 ELSE 0 END) AS walk_in,
    SUM(CASE WHEN admission_type = 'Referral'  THEN 1 ELSE 0 END) AS referral,
    SUM(CASE WHEN admission_type = 'Follow-up' THEN 1 ELSE 0 END) AS follow_up,
    SUM(CASE WHEN admission_type = 'Emergency' THEN 1 ELSE 0 END) AS emergency,
    COUNT(*)                                                        AS total
FROM `portofolio-498810.Hospital_analysis.admissions`
GROUP BY referral_source
ORDER BY total DESC;

-- ============================================================
--  BAGIAN 4 : PERFORMA CABANG (Branch Performance)
-- ============================================================

-- 4.1 Performa keseluruhan per cabang
SELECT
    branch_id,
    COUNT(*)                                        AS total_admisi,
    ROUND(AVG(length_of_stay_days), 2)              AS avg_los,
    SUM(CASE WHEN admission_type = 'Emergency'
             THEN 1 ELSE 0 END)                     AS total_emergency,
    ROUND(
        SUM(CASE WHEN admission_type = 'Emergency'
                 THEN 1 ELSE 0 END) * 100.0
        / COUNT(*), 1
    )                                               AS emergency_rate_pct,
    COUNT(DISTINCT doctor_id)                       AS jumlah_dokter,
    COUNT(DISTINCT patient_id)                      AS pasien_unik
FROM `portofolio-498810.Hospital_analysis.admissions`
GROUP BY branch_id
ORDER BY total_admisi DESC;

-- 4.2 Pertumbuhan per cabang: 2024 vs 2025
WITH yearly AS (
    SELECT
        branch_id,
        EXTRACT(YEAR FROM admission_date) AS tahun,
        COUNT(*) AS total
    FROM `portofolio-498810.Hospital_analysis.admissions`
    GROUP BY branch_id, tahun
)
SELECT
    y24.branch_id,
    y24.total                                               AS admisi_2024,
    y25.total                                               AS admisi_2025,
    ROUND((y25.total - y24.total) * 100.0 / y24.total, 1)  AS growth_pct
FROM yearly y24
JOIN yearly y25 ON y24.branch_id = y25.branch_id
               AND y24.tahun = 2024
               AND y25.tahun = 2025
ORDER BY growth_pct DESC;

-- 4.3 Ranking cabang berdasarkan volume emergency (window function)
WITH emergency_summary AS (
    SELECT
        branch_id,
        COUNT(*) AS total_emergency
    FROM `portofolio-498810.Hospital_analysis.admissions`
    WHERE admission_type = 'Emergency'
    GROUP BY branch_id
)
SELECT
    branch_id,
    total_emergency,
    RANK() OVER (ORDER BY total_emergency DESC) AS ranking_emergency
FROM emergency_summary;

-- ============================================================
--  BAGIAN 5 : ANALISIS KELAS KAMAR
-- ============================================================

-- 5.1 Distribusi kelas kamar
SELECT
    room_class,
    COUNT(*)                                    AS total,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS persen,
    ROUND(AVG(length_of_stay_days), 2)          AS avg_los
FROM `portofolio-498810.Hospital_analysis.admissions`
GROUP BY room_class
ORDER BY total DESC;

-- 5.2 Kelas kamar per tipe admisi (pivot)
SELECT
    admission_type,
    SUM(CASE WHEN room_class = 'Standard'  THEN 1 ELSE 0 END) AS standard,
    SUM(CASE WHEN room_class = 'Deluxe'    THEN 1 ELSE 0 END) AS deluxe,
    SUM(CASE WHEN room_class = 'Executive' THEN 1 ELSE 0 END) AS executive,
    COUNT(*)                                                    AS total
FROM `portofolio-498810.Hospital_analysis.admissions`
GROUP BY admission_type
ORDER BY total DESC;

-- 5.3 Peluang upsell: pasien corporate/asuransi yang masih di Standard
SELECT
    referral_source,
    COUNT(*)    AS total_di_standard,
    ROUND(COUNT(*) * 100.0
          / SUM(COUNT(*)) OVER (PARTITION BY referral_source), 1) AS pct_dari_sumber
FROM `portofolio-498810.Hospital_analysis.admissions`
WHERE room_class = 'Standard'
  AND referral_source IN ('Corporate Partner', 'Insurance Network')
GROUP BY referral_source;

-- ============================================================
--  BAGIAN 6 : DIAGNOSIS
-- ============================================================

-- 6.1 Top 10 diagnosis terbanyak
SELECT
    diagnosis_group,
    COUNT(*)                                    AS total,
    ROUND(AVG(length_of_stay_days), 2)          AS avg_los,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS persen
FROM `portofolio-498810.Hospital_analysis.admissions`
GROUP BY diagnosis_group
ORDER BY total DESC
LIMIT 10;

-- 6.2 Rata-rata LOS per diagnosis — identifikasi yang paling lama
SELECT
    diagnosis_group,
    COUNT(*)                           AS total_kasus,
    ROUND(AVG(length_of_stay_days), 2) AS avg_los,
    MAX(length_of_stay_days)           AS max_los
FROM `portofolio-498810.Hospital_analysis.admissions`
GROUP BY diagnosis_group
HAVING avg_los > (SELECT AVG(length_of_stay_days) FROM `portofolio-498810.Hospital_analysis.admissions`)
ORDER BY avg_los DESC;

-- 6.3 Kategori lama rawat per diagnosis
SELECT
    diagnosis_group,
    SUM(CASE WHEN length_of_stay_days BETWEEN 1 AND 3 THEN 1 ELSE 0 END) AS singkat_1_3,
    SUM(CASE WHEN length_of_stay_days BETWEEN 4 AND 6 THEN 1 ELSE 0 END) AS normal_4_6,
    SUM(CASE WHEN length_of_stay_days >= 7            THEN 1 ELSE 0 END) AS panjang_7plus,
    COUNT(*)                                                               AS total
FROM `portofolio-498810.Hospital_analysis.admissions`
GROUP BY diagnosis_group
ORDER BY panjang_7plus DESC;

-- ============================================================
--  BAGIAN 7 : ANALISIS RETENSI & LOYALITAS PASIEN
-- ============================================================

-- 7.1 Segmentasi frekuensi kunjungan pasien
SELECT
    CASE
        WHEN kunjungan = 1          THEN '1 kunjungan'
        WHEN kunjungan = 2          THEN '2 kunjungan'
        WHEN kunjungan BETWEEN 3 AND 5 THEN '3–5 kunjungan'
        ELSE '6+ kunjungan'
    END                      AS segmen,
    COUNT(*)                 AS jumlah_pasien,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS persen
FROM (
    SELECT patient_id, COUNT(*) AS kunjungan
    FROM `portofolio-498810.Hospital_analysis.admissions`
    GROUP BY patient_id
) t
GROUP BY segmen
ORDER BY jumlah_pasien DESC;

-- 7.2 Pasien dengan kunjungan terbanyak (top 10 loyal)
SELECT
    patient_id,
    COUNT(*)                           AS total_kunjungan,
    SUM(length_of_stay_days)           AS total_hari_rawat,
    MIN(admission_date)                AS kunjungan_pertama,
    MAX(admission_date)                AS kunjungan_terakhir,
    COUNT(DISTINCT diagnosis_group)    AS variasi_diagnosis,
    COUNT(DISTINCT branch_id)          AS cabang_dikunjungi
FROM `portofolio-498810.Hospital_analysis.admissions`
GROUP BY patient_id
ORDER BY total_kunjungan DESC
LIMIT 10;

-- 7.3 Interval kunjungan ulang per pasien (pakai LAG)
WITH visit_order AS (
    SELECT
        patient_id,
        admission_date,
        LAG(admission_date) OVER (
            PARTITION BY patient_id
            ORDER BY admission_date
        ) AS kunjungan_sebelumnya
    FROM `portofolio-498810.Hospital_analysis.admissions`
)
SELECT
    patient_id,
    admission_date,
    kunjungan_sebelumnya,
    DATE_DIFF(admission_date, kunjungan_sebelumnya, DAY) AS hari_antar_kunjungan
FROM visit_order
WHERE kunjungan_sebelumnya IS NOT NULL
ORDER BY patient_id, admission_date;

-- 7.4 Rata-rata interval antar kunjungan per pasien
WITH visit_order AS (
    SELECT
        patient_id,
        admission_date,
        LAG(admission_date) OVER (
            PARTITION BY patient_id
            ORDER BY admission_date
        ) AS kunjungan_sebelumnya
    FROM `portofolio-498810.Hospital_analysis.admissions`
),
gaps AS (
    SELECT
        patient_id,
        DATE_DIFF(admission_date, kunjungan_sebelumnya, DAY) AS gap_hari
    FROM visit_order
    WHERE kunjungan_sebelumnya IS NOT NULL
)
SELECT
    patient_id,
    COUNT(*)                       AS jumlah_kembali,
    ROUND(AVG(gap_hari), 1)        AS avg_interval_hari,
    MIN(gap_hari)                  AS interval_terpendek,
    MAX(gap_hari)                  AS interval_terpanjang
FROM gaps
GROUP BY patient_id
ORDER BY avg_interval_hari ASC
LIMIT 20;

-- ============================================================
--  BAGIAN 8 : WORKLOAD DOKTER
-- ============================================================

-- 8.1 Beban kerja per dokter
SELECT
    doctor_id,
    COUNT(*)                                AS total_pasien,
    ROUND(AVG(length_of_stay_days), 2)      AS avg_los,
    SUM(CASE WHEN admission_type = 'Emergency' THEN 1 ELSE 0 END) AS emergency_ditangani,
    COUNT(DISTINCT branch_id)               AS cabang_aktif,
    COUNT(DISTINCT diagnosis_group)         AS variasi_diagnosis
FROM `portofolio-498810.Hospital_analysis.admissions`
GROUP BY doctor_id
ORDER BY total_pasien DESC;

-- 8.2 Dokter dengan beban emergency tertinggi
SELECT
    doctor_id,
    COUNT(*)    AS total_emergency,
    RANK() OVER (ORDER BY COUNT(*) DESC) AS ranking
FROM `portofolio-498810.Hospital_analysis.admissions`
WHERE admission_type = 'Emergency'
GROUP BY doctor_id
ORDER BY total_emergency DESC
LIMIT 10;

-- 8.3 Distribusi beban dokter — identifikasi ketimpangan
WITH workload AS (
    SELECT doctor_id, COUNT(*) AS total
    FROM `portofolio-498810.Hospital_analysis.admissions`
    GROUP BY doctor_id
)
SELECT
    MIN(total)              AS beban_min,
    MAX(total)              AS beban_max,
    ROUND(AVG(total), 1)    AS beban_avg,
    ROUND(STDDEV(total), 1) AS stddev_beban
FROM workload;

-- ============================================================
--  BAGIAN 9 : ANALISIS DEPARTEMEN
-- ============================================================

-- 9.1 Performa per departemen
SELECT
    department_id,
    COUNT(*)                                    AS total_admisi,
    ROUND(AVG(length_of_stay_days), 2)          AS avg_los,
    MAX(length_of_stay_days)                    AS max_los,
    ROUND(
        SUM(CASE WHEN admission_type = 'Emergency'
                 THEN 1 ELSE 0 END) * 100.0
        / COUNT(*), 1
    )                                           AS emergency_pct,
    COUNT(DISTINCT doctor_id)                   AS jumlah_dokter
FROM `portofolio-498810.Hospital_analysis.admissions`
GROUP BY department_id
ORDER BY total_admisi DESC;

-- 9.2 Departemen dengan LOS di atas rata-rata (kandidat review efisiensi)
WITH dept_avg AS (
    SELECT
        department_id,
        ROUND(AVG(length_of_stay_days), 2) AS avg_los_dept
    FROM `portofolio-498810.Hospital_analysis.admissions`
    GROUP BY department_id
),
global_avg AS (
    SELECT ROUND(AVG(length_of_stay_days), 2) AS avg_los_global
    FROM `portofolio-498810.Hospital_analysis.admissions`
)
SELECT
    d.department_id,
    d.avg_los_dept,
    g.avg_los_global,
    ROUND(d.avg_los_dept - g.avg_los_global, 2) AS selisih_dari_rata_rata
FROM dept_avg d, global_avg g
WHERE d.avg_los_dept > g.avg_los_global
ORDER BY selisih_dari_rata_rata DESC;

-- ============================================================
--  BAGIAN 10 : KAPASITAS & EFISIENSI OPERASIONAL
-- ============================================================

-- 10.1 Running total admisi kumulatif per cabang (timeline)
SELECT
    branch_id,
    admission_date,
    COUNT(*) OVER (
        PARTITION BY branch_id
        ORDER BY admission_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS admisi_kumulatif
FROM `portofolio-498810.Hospital_analysis.admissions`
ORDER BY branch_id, admission_date;

-- 10.2 Volume admisi per hari dalam seminggu
SELECT
    FORMAT_DATE('%A', admission_date)  AS hari,
    EXTRACT(DAYOFWEEK FROM admission_date) AS urutan_hari,
    COUNT(*)                 AS total_admisi,
    ROUND(AVG(length_of_stay_days), 2) AS avg_los
FROM `portofolio-498810.Hospital_analysis.admissions`
GROUP BY hari, urutan_hari
ORDER BY urutan_hari;

-- 10.3 Cabang dengan rata-rata LOS di atas rata-rata global
WITH branch_los AS (
    SELECT
        branch_id,
        ROUND(AVG(length_of_stay_days), 2) AS avg_los
    FROM `portofolio-498810.Hospital_analysis.admissions`
    GROUP BY branch_id
)
SELECT
    b.branch_id,
    b.avg_los,
    ROUND((SELECT AVG(length_of_stay_days) FROM `portofolio-498810.Hospital_analysis.admissions`), 2) AS avg_global,
    ROUND(b.avg_los - (SELECT AVG(length_of_stay_days) FROM `portofolio-498810.Hospital_analysis.admissions`), 2) AS selisih
FROM branch_los b
WHERE b.avg_los > (SELECT AVG(length_of_stay_days) FROM `portofolio-498810.Hospital_analysis.admissions`)
ORDER BY selisih DESC;

-- ============================================================
--  BAGIAN 11 : DIGITAL & CHANNEL GROWTH
-- ============================================================

-- 11.1 Tren digital booking per bulan
SELECT
    FORMAT_DATE('%Y-%m', admission_date) AS periode,
    COUNT(*)                             AS total_admisi,
    SUM(CASE WHEN referral_source = 'Digital Appointment'
             THEN 1 ELSE 0 END)          AS digital,
    ROUND(
        SUM(CASE WHEN referral_source = 'Digital Appointment'
                 THEN 1 ELSE 0 END) * 100.0
        / COUNT(*), 1
    )                                    AS digital_pct
FROM `portofolio-498810.Hospital_analysis.admissions`
GROUP BY periode
ORDER BY periode;

-- 11.2 Profil pasien digital vs non-digital
SELECT
    CASE WHEN referral_source = 'Digital Appointment'
         THEN 'Digital' ELSE 'Non-Digital' END  AS channel,
    COUNT(*)                                     AS total,
    ROUND(AVG(length_of_stay_days), 2)           AS avg_los,
    ROUND(
        SUM(CASE WHEN room_class = 'Executive' THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*), 1
    )                                            AS pct_executive,
    ROUND(
        SUM(CASE WHEN admission_type = 'Emergency' THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*), 1
    )                                            AS pct_emergency
FROM `portofolio-498810.Hospital_analysis.admissions`
GROUP BY channel;

-- ============================================================
--  END OF FILE — SEMUA QUERY SIAP JALAN DI BIGQUERY
-- ============================================================