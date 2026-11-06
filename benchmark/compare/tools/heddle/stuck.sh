$COMPOSE exec -T db psql -U postgres -d heddle -tAc "select count(*) from executions where status in ('running', 'queued')"
