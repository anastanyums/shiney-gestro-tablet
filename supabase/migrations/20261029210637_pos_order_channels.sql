-- Additive configuration: all existing restaurants keep all four standard choices.
create or replace function private.valid_pos_order_channels(p jsonb)
returns boolean language plpgsql immutable set search_path = '' as $$
declare x jsonb; seen_keys text[] := '{}'; seen_names text[] := '{}'; n text;
begin
 if p is null or jsonb_typeof(p) <> 'array' then return false; end if;
 if jsonb_array_length(p) < 4 or jsonb_array_length(p) > 20 then return false; end if;
 for x in select value from jsonb_array_elements(p) loop
  if jsonb_typeof(x) <> 'object' or jsonb_typeof(x->'key') is distinct from 'string'
   or jsonb_typeof(x->'label') is distinct from 'string' or jsonb_typeof(x->'type') is distinct from 'string'
   or jsonb_typeof(x->'enabled') is distinct from 'boolean' then return false; end if;
  n := btrim(x->>'label');
  if n <> x->>'label' or length(n) < 1 or length(n) > 48 or n ~ '[[:cntrl:]]'
   or x->>'key' = any(seen_keys) or lower(n) = any(seen_names)
   or x->>'type' not in ('takeaway','delivery') then return false; end if;
  case x->>'key'
   when 'takeaway' then if n <> 'Takeaway' or x->>'type' <> 'takeaway' then return false; end if;
   when 'phone' then if n <> 'Phone / own delivery' or x->>'type' <> 'delivery' then return false; end if;
   when 'ubereats' then if n <> 'Uber Eats' or x->>'type' <> 'delivery' then return false; end if;
   when 'pickme' then if n <> 'PickMe' or x->>'type' <> 'delivery' then return false; end if;
   else if x->>'key' !~ '^custom_[a-z0-9_-]{8,48}$' then return false; end if;
  end case;
  seen_keys := array_append(seen_keys,x->>'key'); seen_names := array_append(seen_names,lower(n));
 end loop;
 return seen_keys @> array['takeaway','phone','ubereats','pickme'];
end $$;
revoke all on function private.valid_pos_order_channels(jsonb) from public,anon;
grant execute on function private.valid_pos_order_channels(jsonb) to authenticated;

alter table public.restaurants add column pos_order_channels jsonb not null default
'[{"key":"takeaway","label":"Takeaway","type":"takeaway","enabled":true},{"key":"phone","label":"Phone / own delivery","type":"delivery","enabled":true},{"key":"ubereats","label":"Uber Eats","type":"delivery","enabled":true},{"key":"pickme","label":"PickMe","type":"delivery","enabled":true}]'::jsonb;
alter table public.restaurants add constraint restaurants_pos_order_channels_valid check (private.valid_pos_order_channels(pos_order_channels));

create or replace function private.save_pos_order_channels(p_channels jsonb,p_expected jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare rid uuid; current_value jsonb;
begin
 if auth.uid() is null or private.my_role() is distinct from 'restaurant_admin' then
  raise exception 'Only the restaurant owner can change order types' using errcode='42501';
 end if;
 rid := private.my_restaurant_id();
 if rid is null then raise exception 'No restaurant selected' using errcode='42501'; end if;
 if not private.valid_pos_order_channels(p_channels) then raise exception 'Enter unique order type names of 1–48 characters and keep the four standard types' using errcode='22023'; end if;
 select pos_order_channels into current_value from public.restaurants where id=rid for update;
 if not found then raise exception 'Restaurant unavailable' using errcode='42501'; end if;
 if p_expected is null or current_value is distinct from p_expected then raise exception 'Order types changed elsewhere. Reload the settings before saving.' using errcode='40001'; end if;
 update public.restaurants set pos_order_channels=p_channels where id=rid;
 return p_channels;
end $$;
revoke all on function private.save_pos_order_channels(jsonb,jsonb) from public,anon;
grant execute on function private.save_pos_order_channels(jsonb,jsonb) to authenticated;
create or replace function public.update_pos_order_channels(p_channels jsonb,p_expected jsonb)
returns jsonb language sql security invoker set search_path = '' as $$ select private.save_pos_order_channels(p_channels,p_expected); $$;
revoke all on function public.update_pos_order_channels(jsonb,jsonb) from public,anon;
grant execute on function public.update_pos_order_channels(jsonb,jsonb) to authenticated;

-- Enforce owner choices for new POS orders, including orders sent by older clients.
-- Unchanged historical orders can still be fulfilled and paid after a type is disabled.
create or replace function private.guard_pos_order_channel()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
 if new.order_type='dine_in' then return new; end if;
 if tg_op='UPDATE' then
  if new.restaurant_id is not distinct from old.restaurant_id and new.channel is not distinct from old.channel and new.order_type is not distinct from old.order_type then return new; end if;
 end if;
 if not exists(select 1 from public.restaurants r cross join lateral jsonb_array_elements(r.pos_order_channels) c
  where r.id=new.restaurant_id and (c->>'enabled')::boolean and c->>'label'=new.channel and c->>'type'=new.order_type) then
  raise exception 'This order type is unavailable. Choose an enabled order type in Guest & order.' using errcode='22023';
 end if;
 return new;
end $$;
revoke all on function private.guard_pos_order_channel() from public,anon,authenticated;
create trigger pos_order_channel_guard before insert or update of channel,order_type,restaurant_id on public.table_sessions for each row execute function private.guard_pos_order_channel();
notify pgrst,'reload schema';
