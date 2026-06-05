output "catalog_database_name" { value = aws_glue_catalog_database.fleet.name }
output "crawler_name"          { value = aws_glue_crawler.fleet.name }
output "etl_job_name"          { value = aws_glue_job.fleet_etl.name }
output "athena_workgroup_name" { value = aws_athena_workgroup.fleet.name }
