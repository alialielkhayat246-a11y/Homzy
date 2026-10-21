-- Write path for the daily WhatsApp reader (runs on Ali's PC). Secret-gated:
-- only the sha256 of the secret lives here; the secret itself stays on that PC.
-- Rows land as PENDING in catalog_updates — nothing touches the live catalog
-- until an admin applies them from /updates.
create or replace function public.wa_ingest_updates(p_secret text, p_rows jsonb, p_groups jsonb default '[]'::jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n_in int := 0; n_new int := 0; r jsonb; g jsonb;
begin
  if encode(sha256(convert_to(coalesce(p_secret,''), 'utf8')), 'hex')
     <> '572b4929b91ac95e2df4f6d68300c4958fb5f83a8b522509a030bf7b9fadb233' then
    raise exception 'forbidden';
  end if;
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    n_in := n_in + 1;
    insert into catalog_updates (group_name, sender, message_at, message_text, has_media, msg_hash,
                                 developer_id, project_id, project_name_raw, kind, summary_ar, extracted)
    values (r->>'group_name', r->>'sender', nullif(r->>'message_at','')::timestamptz, r->>'message_text',
            nullif(r->>'has_media',''), r->>'msg_hash',
            nullif(r->>'developer_id','')::uuid, nullif(r->>'project_id','')::uuid, r->>'project_name_raw',
            coalesce(nullif(r->>'kind',''), 'other'), r->>'summary_ar', coalesce(r->'extracted', '{}'::jsonb))
    on conflict (msg_hash) do nothing;
    if found then n_new := n_new + 1; end if;
  end loop;
  for g in select * from jsonb_array_elements(coalesce(p_groups, '[]'::jsonb)) loop
    insert into wa_sync_state (group_name, developer_id, last_message_at, last_run_at)
    values (g->>'group_name', nullif(g->>'developer_id','')::uuid, nullif(g->>'last_message_at','')::timestamptz, now())
    on conflict (group_name) do update set
      last_run_at = now(),
      developer_id = coalesce(excluded.developer_id, wa_sync_state.developer_id),
      last_message_at = greatest(wa_sync_state.last_message_at, excluded.last_message_at);
  end loop;
  return jsonb_build_object('received', n_in, 'new', n_new);
end $$;
revoke all on function public.wa_ingest_updates(text, jsonb, jsonb) from public;
grant execute on function public.wa_ingest_updates(text, jsonb, jsonb) to anon, authenticated;
