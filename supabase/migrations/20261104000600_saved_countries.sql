-- Countries on your wishlist: somewhere you want to go, saved as a whole country. Private to you.

create table public.saved_countries (
  owner_id uuid not null references public.profiles (id) on delete cascade,
  country_code character(2) not null references public.countries (code),
  added_at timestamptz not null default now(),
  primary key (owner_id, country_code)
);
alter table public.saved_countries enable row level security;

create or replace function public.my_saved_countries()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(s.country_code::text order by s.added_at desc)
                   from public.saved_countries s where s.owner_id=v_me),'[]'::jsonb);
end$$;

create or replace function public.set_country_saved(p_code text, p_name text, p_present boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_code text;
begin
  v_code:=app_private.upsert_country(p_code,p_name);
  if v_code is null then perform app_private.validation_error('Choose a country.'); end if;
  if p_present then
    insert into public.saved_countries(owner_id,country_code) values(v_me,v_code) on conflict do nothing;
  else
    delete from public.saved_countries where owner_id=v_me and country_code=v_code;
  end if;
  return public.my_saved_countries();
end$$;

revoke execute on function public.my_saved_countries(), public.set_country_saved(text,text,boolean) from public, anon;
grant execute on function public.my_saved_countries(), public.set_country_saved(text,text,boolean) to authenticated;
