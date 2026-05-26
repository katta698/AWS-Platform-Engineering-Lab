output "alb_sg_id"          { value = aws_security_group.alb.id }
output "ec2_sg_id"          { value = aws_security_group.ec2.id }
output "vpce_sg_id"         { value = aws_security_group.vpc_endpoints.id }
