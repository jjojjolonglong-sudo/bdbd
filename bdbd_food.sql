-- bdbd 음식 데이터베이스 (2026-11-10, Claude가 커넥터로 실행)
-- 공공데이터(식약처 식품영양성분 통합DB) + 카페·빵집 메뉴를 한 테이블에. 모든 값은 기준량(base, 보통 100g·100ml) 당.
-- 앱은 검색할 때 맞는 줄만 서버에서 받아요(전체를 내려받지 않음).
create extension if not exists pg_trgm with schema extensions;

create table if not exists bdbd_food (
  id    text primary key,          -- 식품코드(공공데이터) 또는 카페 메뉴 코드(예: cafe-sbux-001)
  n     text not null,             -- 이름
  kind  text not null,             -- 음식 · 원재료 · 가공 · 카페
  maker text,                      -- 제조사/브랜드
  base  text not null default '100g', -- 영양성분 기준량
  k real, c real, p real, f real, su real, -- 열량 kcal · 탄수화물 · 단백질 · 지방 · 당류 (g)
  wt    text,                      -- 1개(1회) 무게·용량 (예: 200g, 355ml)
  s     text generated always as (n || ' ' || coalesce(maker,'')) stored -- 검색용
);
comment on table bdbd_food is 'bdbd 음식 데이터베이스(공공데이터+카페 메뉴). 값은 base(기준량)당. 쓰기는 bdbd_food_put 함수로만';
create index if not exists bdbd_food_s_trgm on bdbd_food using gin (s extensions.gin_trgm_ops);
alter table bdbd_food enable row level security;
drop policy if exists "read all" on bdbd_food;
create policy "read all" on bdbd_food for select to authenticated using (true);

-- 검색: 띄어쓰기로 나눈 낱말이 모두 들어간 것. 이름이 똑같은 것 → 이름이 검색어로 시작하는 것 → 카페·음식·원재료·가공 순 → 짧은 이름 순
create or replace function bdbd_food_search(q text, lim int default 60)
returns setof bdbd_food language sql stable set search_path = public, extensions as $$
  with w as (select array_remove(string_to_array(trim(regexp_replace(q,'\s+',' ','g')),' '),'') a)
  select f.* from bdbd_food f, w
  where (select bool_and(f.s ilike '%' || replace(replace(x,'%','\%'),'_','\_') || '%') from unnest(w.a) x)
  order by (f.n = trim(q)) desc, (f.n ilike replace(replace(trim(q),'%','\%'),'_','\_') || '%') desc,
           case f.kind when '카페' then 0 when '음식' then 1 when '원재료' then 2 else 3 end, length(f.n)
  limit least(greatest(lim,1),200)
$$;

-- 넣기·고치기: 앱 주인 계정만(다른 사람은 실행해도 거절). 데이터 갱신할 때 씀
create or replace function bdbd_food_put(rows jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if auth.uid() is distinct from '10ae410a-cfc1-490e-b347-050b3e38c62e'::uuid then raise exception 'not allowed'; end if;
  insert into bdbd_food(id,n,kind,maker,base,k,c,p,f,su,wt)
  select r->>'id', r->>'n', r->>'kind', nullif(r->>'maker',''), coalesce(nullif(r->>'base',''),'100g'),
         (r->>'k')::real, (r->>'c')::real, (r->>'p')::real, (r->>'f')::real, (r->>'su')::real, nullif(r->>'wt','')
  from jsonb_array_elements(rows) r
  on conflict (id) do update set n=excluded.n, kind=excluded.kind, maker=excluded.maker, base=excluded.base,
    k=excluded.k, c=excluded.c, p=excluded.p, f=excluded.f, su=excluded.su, wt=excluded.wt;
  get diagnostics n = row_count; return n;
end $$;
revoke all on function bdbd_food_put(jsonb) from public, anon;
grant execute on function bdbd_food_put(jsonb) to authenticated;
