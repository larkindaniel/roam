-- M5: a Visit's public note and photos are member content that can be reported, including a
-- retained memory whose rating post was removed. Reports stay operator-only (M2 rules).
alter type public.report_target add value if not exists 'visit';
