with subjects as (
    select
        distinct p.subject_id,
        a.hadm_id,
        p.gender,
        round(
            (
                (cast(a.admittime as date) - cast(p.dob as date)) / (365)
            )
        ) age,
        max(
            case
                when substr(di.icd9_code, 1, 3) = '410' then 'yes'
                else 'no'
            end
        ) heart_attack,
        max(
            case
                when hospital_expire_flag = 1 then 'yes'
                else 'no'
            end
        ) deceased
    from
        patients p
        inner join admissions a on p.subject_id = a.subject_id
        inner join diagnoses_icd di on a.subject_id = di.subject_id
        and a.hadm_id = di.hadm_id --where
        --	a.admission_type in ('urgent', 'emergency')
    group by
        p.subject_id,
        a.hadm_id,
        p.gender,
        round(
            (
                (cast(a.admittime as date) - cast(p.dob as date)) / (365)
            )
        )
),
cardiacs as (
    select
        subject_id,
        hadm_id,
        json_agg(
            json_build_object(
                'charttime',
                charttime,
                'scan_type',
                description,
                'text',
                regexp_replace(
                    replace(replace(text, '   ', ' '), '_', ' '),
                    '\n',
                    ' ',
                    'g'
                )
            )
            order by
                charttime
        ) as radiology_report
    from
        noteevents
    where
        category = 'Radiology'
        and lower(description) like '%cardiac%'
    group by
        subject_id,
        hadm_id
),
diagnoses as (
    select
        subject_id,
        hadm_id,
        json_agg(distinct did.long_title) diagnoses
    from
        diagnoses_icd di
        inner join d_icd_diagnoses did on di.icd9_code = did.icd9_code
    group by
        subject_id,
        hadm_id
),
ecg as (
    select
        subject_id,
        hadm_id,
        json_agg(
            jsonb_build_object(
                'chartdate',
                chartdate,
                'report ',
                regexp_replace(
                    replace(replace(text, '   ', ' '), '_', ' '),
                    '\n',
                    ' ',
                    'g'
                )
            )
            order by
                chartdate
        ) as ecg_report
    from
        noteevents
    where
        category = 'ECG'
        and hadm_id is not null
    group by
        subject_id,
        hadm_id
),
troponin as (
    select
        l.subject_id,
        l.HADM_ID,
        json_agg(
            json_build_object(
                'charttime',
                l.CHARTTIME,
                'label',
                dl.label,
                'value',
                l.VALUE || ' ' || l.VALUEUOM,
                'flag',
                l.FLAG
            )
            order by
                l.charttime
        ) as lab_report
    from
        LABEVENTS L
        inner join D_LABITEMS DL on l.ITEMID = dl.ITEMID
    where
        lower(label) like '%troponin%'
        and hadm_id is not null
    group by
        l.subject_id,
        l.HADM_ID
),
discharge as (
    select
        subject_id,
        hadm_id,
        json_agg(
            json_build_object(
                'report_date',
                to_char(chartdate, 'YYYY-MM-DD'),
                'notes',
                regexp_replace(
                    replace(replace(text, '   ', ' '), '_', ' '),
                    '\n',
                    ' ',
                    'g'
                )
            )
            order by
                chartdate
        ) discharge_notes
    from
        noteevents n
    where
        n.CATEGORY = 'Discharge summary'
    group by
        subject_id,
        hadm_id
)
select
    s.subject_id,
    s.hadm_id,
    s.gender,
    s.age,
    s.heart_attack,
    s.deceased,
    d.diagnoses,
    c.radiology_report,
    e.ecg_report,
    t.lab_report,
    disc.discharge_notes
from
    subjects s
    inner join cardiacs c on s.hadm_id = c.hadm_id
    inner join diagnoses d on s.subject_id = d.subject_id
    and s.hadm_id = d.hadm_id
    inner join ecg e on s.subject_id = e.subject_id
    and s.hadm_id = e.hadm_id
    inner join discharge disc on s.subject_id = disc.subject_id
    and s.hadm_id = disc.hadm_id
    left outer join troponin t on s.subject_id = t.subject_id
    and s.hadm_id = t.hadm_id