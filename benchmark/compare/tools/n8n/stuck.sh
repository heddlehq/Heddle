$COMPOSE exec -T db psql -U postgres -d n8n -tAc "select count(*) from execution_entity where status in ('new', 'running', 'waiting')"
