-- =====================================================================
-- Control de Gastos · base de datos para Supabase
-- Pega TODO este archivo en Supabase → SQL Editor → New query → Run.
-- Se puede volver a correr: no borra datos existentes.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- tablas ----------
create table if not exists public.perfiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text not null,
  nombre     text not null default '',
  persona    text not null default '',          -- cómo aparece en TIPO (ej. ELBA KATTAN)
  rol        text not null default 'usuario' check (rol in ('admin', 'usuario')),
  activo     boolean not null default false,
  creado_el  timestamptz not null default now()
);

create table if not exists public.controles (
  id                 text primary key,
  nombre             text not null,
  corto              text not null default '',
  tipo               text not null default 'mensual' check (tipo in ('mensual', 'proyecto')),
  personas           text[] not null default '{}',
  categorias         text[] not null default '{}',
  incluye            text not null default '',
  excluye            text not null default '',
  tipo_defecto       text not null default 'COMPARTIDO',
  sugerir_por_nombre boolean not null default false,
  color              text not null default 'a',
  estado             text not null default 'abierto' check (estado in ('abierto', 'cerrado')),
  abierto_el         date,
  cerrado_el         date,
  orden              int not null default 0,
  creado_el          timestamptz not null default now()
);

create table if not exists public.accesos (
  usuario uuid not null references public.perfiles(id) on delete cascade,
  control text not null references public.controles(id) on delete cascade,
  primary key (usuario, control)
);

create table if not exists public.movimientos (
  id           uuid primary key default gen_random_uuid(),
  control      text not null references public.controles(id) on delete cascade,
  mes          text not null,                    -- 'AAAA-MM' o 'general' en proyectos
  lado         text not null check (lado in ('egreso', 'ingreso')),
  fecha        date,
  tipo         text not null default '',         -- COMPARTIDO o la persona
  cat          text not null default '',
  sub          text not null default '',
  descripcion  text not null default '',
  detalle      text not null default '',
  valor        numeric(14, 2) not null default 0,
  tx_id        text unique,                      -- ID del registro en la app
  estado       text not null default 'valido' check (estado in ('valido', 'pendiente', 'rechazado')),
  origen       text not null default 'manual' check (origen in ('app', 'manual', 'usuario')),
  creado_por   uuid default auth.uid() references public.perfiles(id) on delete set null,
  creado_el    timestamptz not null default now(),
  validado_por uuid references public.perfiles(id) on delete set null,
  validado_el  timestamptz,
  nota         text not null default ''
);
create index if not exists movimientos_control_mes on public.movimientos (control, mes);

create table if not exists public.tx_mes (          -- movimientos crudos de la app, por mes (solo admin)
  mes          text primary key,
  rows         jsonb not null default '[]'::jsonb,
  n            int not null default 0,
  sincronizado timestamptz
);

create table if not exists public.ignorados (       -- registros de la app que no van en ningún control
  tx_id     text primary key,
  motivo    text not null default '',
  creado_el timestamptz not null default now()
);

create table if not exists public.ajustes (
  clave text primary key,
  valor jsonb
);

-- ---------- funciones de permisos ----------
create or replace function public.es_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfiles where id = auth.uid() and rol = 'admin' and activo);
$$;

create or replace function public.puede_ver(c text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.es_admin() or exists (
    select 1 from accesos a join perfiles p on p.id = a.usuario
    where a.usuario = auth.uid() and a.control = c and p.activo);
$$;

create or replace function public.control_abierto(c text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from controles where id = c and estado = 'abierto');
$$;

-- Cada cuenta nueva recibe un perfil. La PRIMERA cuenta es el administrador;
-- las demás quedan inactivas hasta que el administrador les da acceso.
create or replace function public.nuevo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
declare primero boolean;
begin
  perform pg_advisory_xact_lock(4815162342);
  primero := not exists (select 1 from perfiles);
  insert into perfiles (id, email, nombre, rol, activo)
  values (new.id, coalesce(new.email, ''), coalesce(new.raw_user_meta_data ->> 'nombre', ''),
          case when primero then 'admin' else 'usuario' end, primero)
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists al_crear_usuario on auth.users;
create trigger al_crear_usuario after insert on auth.users
  for each row execute function public.nuevo_usuario();

-- Un usuario no administrador no puede cambiar campos de validación ni hacerse admin.
create or replace function public.proteger_movimiento() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.es_admin() then return new; end if;
  new.estado := 'pendiente';
  new.origen := 'usuario';
  new.tx_id := null;
  new.validado_por := null;
  new.validado_el := null;
  if tg_op = 'INSERT' then
    new.creado_por := auth.uid();
    new.creado_el := now();
  else
    new.creado_por := old.creado_por;
    new.creado_el := old.creado_el;
    new.nota := old.nota;
  end if;
  return new;
end $$;

drop trigger if exists proteger_movimiento on public.movimientos;
create trigger proteger_movimiento before insert or update on public.movimientos
  for each row execute function public.proteger_movimiento();

-- ---------- seguridad por filas (RLS) ----------
alter table public.perfiles    enable row level security;
alter table public.controles   enable row level security;
alter table public.accesos     enable row level security;
alter table public.movimientos enable row level security;
alter table public.tx_mes      enable row level security;
alter table public.ignorados   enable row level security;
alter table public.ajustes     enable row level security;

drop policy if exists perfiles_ver on public.perfiles;
create policy perfiles_ver on public.perfiles for select to authenticated using (id = auth.uid() or public.es_admin());
drop policy if exists perfiles_admin_upd on public.perfiles;
create policy perfiles_admin_upd on public.perfiles for update to authenticated using (public.es_admin()) with check (public.es_admin());
drop policy if exists perfiles_admin_del on public.perfiles;
create policy perfiles_admin_del on public.perfiles for delete to authenticated using (public.es_admin() and id <> auth.uid());

drop policy if exists controles_ver on public.controles;
create policy controles_ver on public.controles for select to authenticated using (public.puede_ver(id));
drop policy if exists controles_admin on public.controles;
create policy controles_admin on public.controles for all to authenticated using (public.es_admin()) with check (public.es_admin());

drop policy if exists accesos_ver on public.accesos;
create policy accesos_ver on public.accesos for select to authenticated using (usuario = auth.uid() or public.es_admin());
drop policy if exists accesos_admin on public.accesos;
create policy accesos_admin on public.accesos for all to authenticated using (public.es_admin()) with check (public.es_admin());

drop policy if exists mov_ver on public.movimientos;
create policy mov_ver on public.movimientos for select to authenticated using (public.puede_ver(control));
drop policy if exists mov_admin on public.movimientos;
create policy mov_admin on public.movimientos for all to authenticated using (public.es_admin()) with check (public.es_admin());
drop policy if exists mov_usuario_ins on public.movimientos;
create policy mov_usuario_ins on public.movimientos for insert to authenticated
  with check (public.puede_ver(control) and public.control_abierto(control));
drop policy if exists mov_usuario_upd on public.movimientos;
create policy mov_usuario_upd on public.movimientos for update to authenticated
  using (creado_por = auth.uid() and estado = 'pendiente')
  with check (creado_por = auth.uid() and public.puede_ver(control) and public.control_abierto(control));
drop policy if exists mov_usuario_del on public.movimientos;
create policy mov_usuario_del on public.movimientos for delete to authenticated
  using (creado_por = auth.uid() and estado in ('pendiente', 'rechazado'));

drop policy if exists tx_admin on public.tx_mes;
create policy tx_admin on public.tx_mes for all to authenticated using (public.es_admin()) with check (public.es_admin());
drop policy if exists ign_admin on public.ignorados;
create policy ign_admin on public.ignorados for all to authenticated using (public.es_admin()) with check (public.es_admin());
drop policy if exists aj_admin on public.ajustes;
create policy aj_admin on public.ajustes for all to authenticated using (public.es_admin()) with check (public.es_admin());

revoke all on all tables in schema public from anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on function public.es_admin(), public.puede_ver(text), public.control_abierto(text) to authenticated;

-- ---------- datos iniciales ----------
insert into public.controles (id, nombre, corto, tipo, categorias, tipo_defecto, sugerir_por_nombre, color, orden) values
  ('FAM', 'Gastos Familiares', 'Familia', 'mensual', '{8.}', 'COMPARTIDO', false, 'a', 1),
  ('CR',  'Gastos de mis padres', 'Padres', 'mensual', '{6.}', 'COMPARTIDO', true, 'b', 2)
on conflict (id) do nothing;
insert into public.ajustes (clave, valor) values ('inicio', to_jsonb(to_char(date_trunc('month', now()), 'YYYY-MM-DD')))
on conflict (clave) do nothing;
