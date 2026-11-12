-- ReSky themes: Classic Blue + Dark Mode are free; Sunset, Green Nature, Neon, Winter,
-- Minimalist and Retro require ReSky Plus. The founder always passes has_plus(), so every
-- theme is unlocked on the founder account. (Safe to run on databases created before this.)

alter table public.profiles alter column theme_id set default 'classic_blue';

insert into public.cosmetic_items (id, kind, name, is_premium, is_released, founder_only, payload, sort_order) values
  ('classic_blue', 'theme', 'Classic Blue', false, true, false, '{"primary":"#00AFF0","background":"#EAF6FD","bubble":"#D9F1FD","dark":false}', 0),
  ('dark_mode',    'theme', 'Dark Mode',    false, true, false, '{"primary":"#1E9BF0","background":"#0E1621","bubble":"#173149","dark":true}', 1),
  ('sunset',       'theme', 'Sunset',       true,  true, false, '{"primary":"#F0743E","background":"#FFF3EA","bubble":"#FFE0C7","dark":false}', 2),
  ('green_nature', 'theme', 'Green Nature', true,  true, false, '{"primary":"#3FA535","background":"#F1F9EA","bubble":"#DDF2CF","dark":false}', 3),
  ('neon',         'theme', 'Neon',         true,  true, false, '{"primary":"#B44CFF","background":"#0D0A16","bubble":"#2A1840","dark":true}', 4),
  ('winter',       'theme', 'Winter',       true,  true, false, '{"primary":"#2E9BE0","background":"#EEF7FD","bubble":"#DCEFFB","dark":false}', 5),
  ('minimalist',   'theme', 'Minimalist',   true,  true, false, '{"primary":"#1E88E5","background":"#F6F9FC","bubble":"#EAF2FB","dark":false}', 6),
  ('retro',        'theme', 'Retro',        true,  true, false, '{"primary":"#2A6EDB","background":"#EEF3FC","bubble":"#DCE8FA","dark":false}', 7)
on conflict (id) do update set kind = excluded.kind, name = excluded.name, is_premium = excluded.is_premium,
  is_released = excluded.is_released, founder_only = excluded.founder_only, payload = excluded.payload,
  sort_order = excluded.sort_order;

-- Move anyone on an old placeholder theme to its closest new one
update public.profiles set theme_id = case theme_id
    when 'midnight' then 'dark_mode'
    when 'aurora' then 'neon'
    when 'sunset_cloud' then 'sunset'
    when 'retro2009' then 'retro'
    when 'aero' then 'winter'
    else 'classic_blue' end
  where theme_id not in ('classic_blue', 'dark_mode', 'sunset', 'green_nature', 'neon', 'winter', 'minimalist', 'retro');

delete from public.cosmetic_items
  where kind = 'theme'
    and id not in ('classic_blue', 'dark_mode', 'sunset', 'green_nature', 'neon', 'winter', 'minimalist', 'retro');

-- Only real theme ids may be stored
alter table public.profiles drop constraint if exists profiles_theme_valid;
alter table public.profiles add constraint profiles_theme_valid
  check (theme_id in ('classic_blue', 'dark_mode', 'sunset', 'green_nature', 'neon', 'winter', 'minimalist', 'retro'));
