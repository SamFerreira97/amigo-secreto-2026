select md5(jsonb_build_object(
 'participants',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.participants x),
 'event',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.event x),
 'photos',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.participant_directory x),
 'status',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.participation_status x),
 'assignments',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from private.code_assignments x),
 'wishes',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from private.code_wishes x),
 'pins',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from private.profile_access x),
 'sessions',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from private.code_sessions x),
 'audit',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from private.admin_audit x),
 'legacy_assignments',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.assignments x),
 'legacy_wishes',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.wishes x),
 'legacy_invites',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from private.enrollment_invites x)
 )::text) as resumo_integridade_edicao1;
