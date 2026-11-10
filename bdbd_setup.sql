-- bdbd(체중·식단 기록) 테이블. 2026-11-10 Claude가 커넥터로 실행 완료(다시 실행해도 안전해요).
-- 다른 앱과 같이 로그인한 본인 행만 읽고 쓸 수 있어요(user_id = auth.uid()).
create table if not exists bdbd_kv (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  key text not null,
  value jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, key)
);
comment on table bdbd_kv is 'bdbd 기록 보관함: key=종류(pf 내 정보, bd 체성분, cf 내 음식, rc 최근 음식, d:날짜 하루 식단·운동), value=내용';
alter table bdbd_kv enable row level security;
drop policy if exists "own rows" on bdbd_kv;
create policy "own rows" on bdbd_kv for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
