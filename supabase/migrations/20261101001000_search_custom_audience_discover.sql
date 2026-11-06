-- Places already on Roam, matched literally by name, so a search reuses them instead of making duplicates.
create or replace function public.search_roam_places(p_query text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); q text:=app_private.normalize_text(coalesce(p_query,''));
begin
  if q='' then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(app_private.experience_summary_json(x.id,v_me) order by x.starts desc,x.name)
    from(select e.id,pl.name,starts_with(pl.normalized_name,q) starts from public.experiences e join public.places pl on pl.id=e.place_id
         where strpos(pl.normalized_name,q)>0 order by starts desc,pl.name limit 10)x),'[]'::jsonb);
end$$;

-- A place someone adds by hand: a name and a map position. Adding the same one again reuses it.
create or replace function public.add_custom_place(p_name text,p_latitude double precision,p_longitude double precision,p_category text,
  p_locality text default null,p_region text default null,p_country_code text default null,p_country_name text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_name text:=btrim(coalesce(p_name,'')); v_place uuid; v_experience uuid; v_country text; v_city uuid; v_category public.experience_category;
begin
  if char_length(v_name) not between 1 and 120 then perform app_private.validation_error('Give this place a name of 120 characters or fewer.'); end if;
  if p_latitude is null or p_longitude is null or p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
    perform app_private.validation_error('Choose where this place is on the map.');
  end if;
  begin v_category:=p_category::public.experience_category;
  exception when invalid_text_representation then perform app_private.validation_error('Choose a category for this place.'); end;
  if v_category is null then perform app_private.validation_error('Choose a category for this place.'); end if;
  select id into v_place from public.places where provider='custom' and normalized_name=app_private.normalize_text(v_name)
    and abs(latitude-p_latitude)<0.0005 and abs(longitude-p_longitude)<0.0005 limit 1;
  if v_place is null then
    v_country:=case when p_country_code is not null then app_private.upsert_country(p_country_code,p_country_name) end;
    v_city:=case when p_country_code is not null and p_locality is not null then app_private.upsert_city(v_country,p_country_name,p_region,p_locality,null,null) end;
    insert into public.places(provider,name,normalized_name,locality,region,country_code,country_name,city_id,latitude,longitude,is_locality,provenance)
    values('custom',v_name,app_private.normalize_text(v_name),p_locality,p_region,v_country,p_country_name,v_city,p_latitude,p_longitude,false,jsonb_build_object('source','member','addedBy',v_me))
    returning id into v_place;
    insert into public.experiences(place_id,category,category_source) values(v_place,v_category,'confirmed') returning id into v_experience;
  else
    select id into v_experience from public.experiences where place_id=v_place;
  end if;
  return app_private.experience_summary_json(v_experience,v_me);
end$$;

create or replace function public.set_visit_audience(p_visit_id uuid,p_audience text)
returns text language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  if p_audience is null or p_audience not in ('friends','only_me','public') then perform app_private.validation_error('Choose who can see this visit.'); end if;
  update public.visits set audience=p_audience,updated_at=now() where id=p_visit_id and owner_id=v_me;
  if not found then raise exception 'roam:not_found' using errcode='P0002'; end if;
  return p_audience;
end$$;

-- Discover now counts places people visited without rating, and friends who have been at all.
create or replace function public.discover_places(p_min_lat double precision default null,p_max_lat double precision default null,
                                                  p_min_lon double precision default null,p_max_lon double precision default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('experience',app_private.experience_summary_json(x.id,v_me),
      'communityScore',x.score,'communityCount',x.raters,
      'friendNames',coalesce((select jsonb_agg(distinct p.display_name)
                              from public.visits v join public.profiles p on p.id=v.owner_id
                              where v.experience_id=x.id and v.owner_id<>v_me and app_private.are_friends(v_me,v.owner_id)
                                and app_private.audience_allows(v.owner_id,v.audience,v_me)),'[]'::jsonb),
      'coverPath',(select m.bucket||'/'||m.object_path from public.media m join public.visits v on v.id=m.visit_id
                   where v.experience_id=x.id and m.state='attached' and app_private.audience_allows(v.owner_id,v.audience,v_me)
                   order by v.created_at desc,m.position limit 1)) order by x.score desc nulls last,x.id)
    from(select e.id,(select round(avg(r.score),1) from public.ratings r where r.experience_id=e.id and app_private.audience_allows(r.owner_id,r.audience,v_me)) score,
                (select count(*)::int from public.ratings r where r.experience_id=e.id and app_private.audience_allows(r.owner_id,r.audience,v_me)) raters
         from public.experiences e join public.places pl on pl.id=e.place_id
         where (p_min_lat is null or pl.latitude between p_min_lat and p_max_lat)
           and (p_min_lon is null or pl.longitude between p_min_lon and p_max_lon)
           and exists(select 1 from public.visits v where v.experience_id=e.id and app_private.audience_allows(v.owner_id,v.audience,v_me))
         order by score desc nulls last,e.id limit 120)x),'[]'::jsonb);
end$$;

revoke execute on function public.search_roam_places(text),public.add_custom_place(text,double precision,double precision,text,text,text,text,text),public.set_visit_audience(uuid,text) from public,anon;
grant execute on function public.search_roam_places(text),public.add_custom_place(text,double precision,double precision,text,text,text,text,text),public.set_visit_audience(uuid,text) to authenticated;
