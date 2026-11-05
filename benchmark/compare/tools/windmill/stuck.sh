$COMPOSE exec -T db psql -U postgres -d windmill -tAc "select count(*) from v2_job_queue"
