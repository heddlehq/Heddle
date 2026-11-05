$COMPOSE exec -T db psql -U postgres -d activepieces -tAc "select count(*) from flow_run where status in ('QUEUED', 'RUNNING', 'PAUSED')"
