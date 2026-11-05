$COMPOSE exec -T db psql -U postgres -d kestra -tAc "select count(*) from executions where state_current in ('CREATED', 'RUNNING', 'RESTARTED', 'QUEUED')"
