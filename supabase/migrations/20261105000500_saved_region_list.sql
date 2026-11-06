-- Saved states and provinces with their names, for My Places' Saved tab.
create or replace function public.my_saved_region_list()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('countryCode', s.country_code::text, 'region', s.region_code, 'name', s.name)
                                    order by s.added_at desc)
                   from public.saved_regions s where s.owner_id=v_me),'[]'::jsonb);
end$$;

revoke execute on function public.my_saved_region_list() from public, anon;
grant execute on function public.my_saved_region_list() to authenticated;
