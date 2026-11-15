-- Reports are about people, places, logs, comments and photos: there are no posts to report any more.
drop function public.submit_report(uuid, public.report_target, uuid, public.report_reason, text);
alter type public.report_target rename to report_target_with_posts;
create type public.report_target as enum ('experience', 'comment', 'media', 'member', 'visit');
alter table public.reports alter column target_type type public.report_target
  using (case when target_type::text = 'activity' then 'visit' else target_type::text end)::public.report_target;
drop type public.report_target_with_posts;

CREATE OR REPLACE FUNCTION public.submit_report(p_operation_id uuid, p_target_type public.report_target, p_target_id uuid, p_reason report_reason, p_body text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  me uuid := app_private.require_member();
  r public.reports;
begin
  if char_length(coalesce(p_body, '')) > 1000 then
    perform app_private.validation_error('Use 1,000 characters or fewer.');
  end if;
  insert into public.reports (id, reporter_id, target_type, target_id, reason, body)
  values (p_operation_id, me, p_target_type, p_target_id, p_reason, nullif(btrim(coalesce(p_body, '')), ''))
  on conflict (id) do nothing;
  select * into r from public.reports where id = p_operation_id and reporter_id = me;
  if not found then
    raise exception 'roam:operation_conflict' using errcode = '23505';
  end if;
  return jsonb_build_object('id', r.id, 'targetKind', r.target_type, 'reason', r.reason, 'status', r.status, 'createdAt', r.created_at);
end;
$function$

;

revoke execute on function public.submit_report(uuid, public.report_target, uuid, public.report_reason, text) from public, anon;
grant execute on function public.submit_report(uuid, public.report_target, uuid, public.report_reason, text) to authenticated;
