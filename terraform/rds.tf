# RDS Database Resources


# RDS Instance
resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-db"
  engine         = "mysql"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 100
  storage_type          = "gp2"
  storage_encrypted     = false  # Set to true for production

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 3306

  multi_az               = var.db_multi_az
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = var.db_backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  skip_final_snapshot       = true  # Set to false for production
  final_snapshot_identifier = "${var.project_name}-db-final-snapshot"

  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]

  tags = {
    Name = "${var.project_name}-db"
  }
}

# Optional: Read Replica for scaling reads
# Uncomment to create a read replica
# resource "aws_db_instance" "read_replica" {
#   identifier             = "${var.project_name}-db-replica"
#   replicate_source_db    = aws_db_instance.main.identifier
#   instance_class         = var.db_instance_class
#   skip_final_snapshot    = true
#   vpc_security_group_ids = [aws_security_group.rds.id]
#
#   tags = {
#     Name = "${var.project_name}-db-replica"
#   }
# }