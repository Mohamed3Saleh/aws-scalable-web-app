# Architecture Deep Dive

## Overview

This document provides an in-depth explanation of the scalable web application architecture deployed on AWS. It covers design decisions, AWS services used, and the rationale behind each component.

## Architecture Diagram Components

### 1. Virtual Private Cloud (VPC)


**Configuration:**
- **CIDR Block:** 10.0.0.0/16 (65,536 IP addresses)
- **DNS Resolution:** Enabled
- **DNS Hostnames:** Enabled

**Why we need it:**
- Provides network isolation and security
- Allows you to define your own IP address range
- Enables control over routing and subnets
- Foundation for all other networking resources

**Design Decision:**
We chose 10.0.0.0/16 because it provides ample IP addresses while following RFC 1918 private network standards. This range is large enough for future expansion.

---

### 2. Subnet Architecture

#### Public Subnets (2 subnets across 2 AZs)

**Configuration:**
- Subnet 1: 10.0.1.0/24 (251 usable IPs) in us-east-1a
- Subnet 2: 10.0.2.0/24 (251 usable IPs) in us-east-1b
- Auto-assign public IPv4: Enabled
- Route to Internet Gateway: Yes

**What goes here:**
- Application Load Balancer
- NAT Gateways
- Bastion hosts (if needed)

**Why public:**
These subnets need direct internet access to receive incoming traffic and provide outbound connectivity for private subnets.

#### Private Subnets (2 subnets across 2 AZs)

**Configuration:**
- Subnet 1: 10.0.3.0/24 (251 usable IPs) in us-east-1a
- Subnet 2: 10.0.4.0/24 (251 usable IPs) in us-east-1b
- Auto-assign public IPv4: Disabled
- Route to NAT Gateway: Yes

**What goes here:**
- EC2 instances (web servers)
- Application servers
- Any compute that shouldn't be directly accessible from internet

**Why private:**
Enhanced security - instances are not directly accessible from internet. They can initiate outbound connections through NAT Gateway but cannot receive unsolicited inbound traffic.

#### Database Subnets (2 subnets across 2 AZs)

**Configuration:**
- Subnet 1: 10.0.5.0/24 (251 usable IPs) in us-east-1a
- Subnet 2: 10.0.6.0/24 (251 usable IPs) in us-east-1b
- Auto-assign public IPv4: Disabled
- Route to Internet: None

**What goes here:**
- RDS database instances
- ElastiCache clusters
- Other data stores

**Why isolated:**
Maximum security - no internet connectivity at all. Only accessible from application layer through security groups.

---

### 3. Internet Gateway


**Key characteristics:**
- Managed by AWS (no maintenance required)
- Automatically redundant and highly available
- No bandwidth constraints
- Free (no additional charge)

**How it works:**
1. Performs NAT for instances with public IP addresses
2. Routes traffic between VPC and internet
3. Supports IPv4 and IPv6

**Route table entry:**
```
Destination: 0.0.0.0/0
Target: igw-xxxxx
```

---

### 4. NAT Gateway


**Configuration:**
- **Count:** 2 (one per Availability Zone)
- **Location:** Public subnets
- **Elastic IP:** One per NAT Gateway

**Why we need it:**
- Private subnet instances need to download software updates
- Access AWS services (S3, DynamoDB, etc.)
- Connect to external APIs
- Cannot receive inbound connections from internet

**High Availability Design:**
We deploy one NAT Gateway per AZ. If one AZ fails, the other continues to work. This prevents NAT Gateway from being a single point of failure.

**Cost consideration:**
NAT Gateways cost ~$0.045/hour + data processing charges (~$0.045/GB). For cost savings in development:
- Consider using a single NAT Gateway
- Or use NAT Instance (requires more management)
- Or remove NAT Gateway if outbound internet not needed

---

### 5. Application Load Balancer (ALB)

**What it is:**
Layer 7 (HTTP/HTTPS) load balancer that distributes incoming application traffic across multiple targets.

**Key features:**
- **Health checks:** Regularly checks target health
- **Path-based routing:** Route based on URL path
- **Host-based routing:** Route based on hostname
- **SSL/TLS termination:** Handles HTTPS encryption
- **WebSocket support:** Maintains persistent connections
- **HTTP/2 support:** Improved performance

**Configuration:**
- **Scheme:** Internet-facing
- **IP Address Type:** IPv4
- **Subnets:** Both public subnets (multi-AZ)
- **Security Group:** Allows HTTP (80) from internet

**Health Check Settings:**
```
Protocol: HTTP
Path: /
Port: 80
Healthy threshold: 2
Unhealthy threshold: 2
Timeout: 5 seconds
Interval: 30 seconds
Success codes: 200
```

**Why these settings:**
- **Path "/":** Simple to implement, works for most apps
- **Threshold 2:** Balance between quick detection and false positives
- **30 second interval:** AWS recommendation for web apps
- **5 second timeout:** Allows for slight delays without marking unhealthy

**Traffic flow:**
1. User sends request to ALB DNS name
2. ALB receives request on port 80
3. ALB checks which targets are healthy
4. ALB forwards request to a healthy target
5. Target processes request and sends response
6. ALB returns response to user

---

### 6. Target Group


**Configuration:**
- **Protocol:** HTTP
- **Port:** 80
- **VPC:** Main VPC
- **Health check:** Enabled
- **Deregistration delay:** 30 seconds

**Deregistration delay explained:**
When an instance is removed from target group (during scale-in or termination), ALB waits 30 seconds before fully removing it. This allows in-flight requests to complete, preventing connection errors.

---

### 7. Auto Scaling Group (ASG)


**Key benefits:**
1. **Automatic Scaling:** Adjusts capacity based on demand
2. **Health Checks:** Replaces unhealthy instances
3. **Load Distribution:** Distributes instances across AZs
4. **Cost Optimization:** Runs only what you need

**Configuration:**
```
Minimum size: 2 instances
Maximum size: 4 instances
Desired capacity: 2 instances
Health check type: ELB
Health check grace period: 300 seconds
```

**Why these settings:**

**Minimum 2:**
- High availability (one per AZ)
- If one fails, app continues running
- Handles normal traffic without scaling

**Maximum 4:**
- Prevents runaway costs
- Sufficient for typical workload spikes
- Can be adjusted based on actual needs

**Health check grace period 300s:**
- Gives instance time to start and initialize
- Instance won't be marked unhealthy during startup
- Typical time for user-data script to complete

**Scaling Policies:**

**Scale-Out Policy:**
- **Trigger:** CPU > 70% for 4 minutes (2 periods of 2 minutes)
- **Action:** Add 1 instance
- **Cooldown:** 300 seconds

**Scale-In Policy:**
- **Trigger:** CPU < 30% for 4 minutes
- **Action:** Remove 1 instance
- **Cooldown:** 300 seconds

**Why these thresholds:**
- 70% is high enough to allow normal spikes
- 30% ensures significant underutilization before scaling down
- Prevents "flapping" (constant scaling up and down)

---

### 8. Launch Template

**What it is:**
A template that contains the configuration information to launch instances.

**Components:**
1. **AMI:** Amazon Linux 2 (latest)
2. **Instance Type:** t2.micro (Free Tier)
3. **Security Groups:** EC2 security group
4. **IAM Instance Profile:** For CloudWatch access
5. **User Data:** Initialization script

**Why Amazon Linux 2:**
- Optimized for AWS
- Long-term support (until 2025)
- Includes AWS CLI pre-installed
- Regular security updates
- Free Tier eligible

**User Data Script:**
Runs automatically when instance launches. Our script:
1. Updates system packages
2. Installs Apache web server
3. Installs MySQL client
4. Creates HTML page with instance info
5. Tests database connectivity
6. Configures Apache for performance
7. Starts Apache service

---

### 9. EC2 Instances

**What they are:**
Virtual servers in the cloud that run your application.

**Configuration:**
- **Type:** t2.micro
- **vCPUs:** 1
- **Memory:** 1 GB
- **Network:** Up to 2048 Mbps
- **Storage:** EBS-backed

**Why t2.micro:**
- Free Tier eligible (750 hours/month first year)
- Sufficient for simple web applications
- Burstable performance for traffic spikes
- Cost-effective (~$8-10/month after Free Tier)

**IAM Role attached:**
Allows instances to:
- Send logs to CloudWatch
- Send metrics to CloudWatch
- Use Systems Manager (for Session Manager access)

**No SSH keys needed:**
We use AWS Systems Manager Session Manager for secure shell access without managing SSH keys.

---

### 10. RDS MySQL Database

**What it is:**
A managed relational database service that handles database management tasks.

**Configuration:**
```
Engine: MySQL 8.0
Instance Class: db.t3.micro
Storage: 20 GB GP2 (SSD)
Multi-AZ: Enabled
Backup Retention: 7 days
Automated Backups: Enabled
Maintenance Window: Sunday 4-5 AM
```

**What AWS manages:**
- Hardware provisioning
- Database setup
- Patching
- Backups
- Failure detection
- Recovery
- Software updates

**What you manage:**
- Database schema
- Queries
- Performance tuning
- Access control

**Multi-AZ Deployment:**
- **Primary:** Active database in one AZ
- **Standby:** Synchronous replica in another AZ
- **Automatic Failover:** If primary fails, standby becomes primary (typically 60-120 seconds)
- **No data loss:** Synchronous replication ensures consistency

**Why Multi-AZ:**
- High availability (99.95% SLA)
- Automatic failover
- No manual intervention needed
- Protection against AZ failure

**Backup Strategy:**
- **Automated Backups:** Daily snapshots
- **Retention:** 7 days
- **Backup Window:** 3-4 AM (low traffic)
- **Point-in-time Recovery:** Restore to any second within retention period

---

### 11. Security Groups

**What they are:**
Virtual firewalls that control inbound and outbound traffic for AWS resources.

**Key characteristics:**
- **Stateful:** Return traffic automatically allowed
- **Default Deny:** All traffic denied unless explicitly allowed
- **No Deny Rules:** Can only create allow rules

#### ALB Security Group

```
Inbound:
  - HTTP (80) from 0.0.0.0/0 (anywhere)
  - HTTPS (443) from 0.0.0.0/0 (optional)

Outbound:
  - All traffic to 0.0.0.0/0
```

**Why allow from anywhere:**
ALB needs to accept traffic from all internet users accessing your application.

#### EC2 Security Group

```
Inbound:
  - HTTP (80) from ALB security group
  - SSH (22) from your IP (for troubleshooting)

Outbound:
  - All traffic to 0.0.0.0/0
```

**Security principles:**
- EC2 only accepts traffic from ALB (not directly from internet)
- SSH restricted to your IP address
- Following principle of least privilege

#### RDS Security Group

```
Inbound:
  - MySQL (3306) from EC2 security group

Outbound:
  - None (not needed for RDS)
```

**Maximum security:**
Database only accessible from application layer, not from internet or other sources.

---

### 12. IAM Roles and Policies

**EC2 IAM Role:**

Allows EC2 instances to:

1. **CloudWatch Logs:**
   ```json
   {
     "Effect": "Allow",
     "Action": [
       "logs:CreateLogGroup",
       "logs:CreateLogStream",
       "logs:PutLogEvents"
     ],
     "Resource": "*"
   }
   ```

2. **CloudWatch Metrics:**
   ```json
   {
     "Effect": "Allow",
     "Action": [
       "cloudwatch:PutMetricData"
     ],
     "Resource": "*"
   }
   ```

3. **Systems Manager:**
   - Enables Session Manager access
   - No SSH keys required
   - All sessions logged to CloudWatch

**Security best practices:**
- Instances use IAM roles (not access keys)
- Credentials automatically rotated
- Fine-grained permissions
- Audit trail in CloudTrail

---

### 13. CloudWatch Monitoring

**Metrics Collected:**

**EC2:**
- CPU Utilization
- Network In/Out
- Disk Read/Write
- Status Checks

**ALB:**
- Request Count
- Target Response Time
- HTTP 4xx/5xx Errors
- Healthy/Unhealthy Host Count

**RDS:**
- CPU Utilization
- Database Connections
- Free Storage Space
- Read/Write IOPS

**Auto Scaling:**
- Group Desired Capacity
- Group In-Service Instances
- Group Total Instances

**Alarms Configured:**

1. **High CPU (EC2):** Triggers scale-out
2. **Low CPU (EC2):** Triggers scale-in
3. **Unhealthy Hosts (ALB):** Sends notification
4. **High CPU (RDS):** Sends notification
5. **Low Storage (RDS):** Sends notification

**CloudWatch Dashboard:**
Visual interface showing all key metrics in one place.

---

## Data Flow

### Normal Request Flow

```
1. User enters ALB DNS name in browser
   └─> DNS resolves to ALB IP addresses

2. Request reaches Application Load Balancer
   └─> ALB checks target health
   └─> Selects healthy target using round-robin

3. Request forwarded to EC2 instance
   └─> Security group allows traffic from ALB
   └─> Apache web server processes request
   └─> Application may query database

4. If database query needed:
   └─> EC2 connects to RDS via private IP
   └─> Security group allows traffic from EC2
   └─> RDS executes query
   └─> Results returned to EC2

5. EC2 generates response
   └─> Sent back through ALB
   └─> ALB returns response to user
```

### Auto Scaling Flow

**Scale-Out:**
```
1. CPU utilization increases above 70%
2. CloudWatch alarm enters "ALARM" state
3. Scale-out policy triggered
4. Auto Scaling launches new instance:
   - Uses launch template
   - Runs user-data script
   - Installs Apache
   - Registers with target group
5. Health check starts (5-minute grace period)
6. Instance becomes "InService"
7. ALB starts sending traffic
```

**Scale-In:**
```
1. CPU utilization drops below 30%
2. CloudWatch alarm enters "ALARM" state
3. Scale-in policy triggered
4. Auto Scaling selects instance to terminate
5. Instance set to "Terminating:Wait"
6. ALB stops sending new requests
7. Existing connections drain (30 seconds)
8. Instance terminated
```

### Failure Scenarios

**EC2 Instance Failure:**
```
1. Instance becomes unhealthy (fails health checks)
2. ALB marks instance as unhealthy
3. ALB stops sending traffic to that instance
4. Auto Scaling detects unhealthy instance
5. Auto Scaling terminates unhealthy instance
6. New instance launched automatically
7. System returns to desired capacity
```

**Availability Zone Failure:**
```
1. Entire AZ becomes unavailable
2. Instances in that AZ fail health checks
3. ALB routes all traffic to healthy AZ
4. Auto Scaling may launch instances in healthy AZ
5. Application continues running (no downtime)
6. RDS automatically fails over to standby (Multi-AZ)
```

**Database Failure (Multi-AZ):**
```
1. Primary database instance fails
2. RDS detects failure (30-60 seconds)
3. Automatic failover to standby replica
4. DNS record updated to standby endpoint
5. Applications reconnect (60-120 seconds total)
6. No data loss (synchronous replication)
```

---

## Scalability Analysis

### Vertical Scaling (Scale Up)

**Current:** t2.micro (1 vCPU, 1 GB RAM)

**Can upgrade to:**
- t2.small: 1 vCPU, 2 GB RAM
- t2.medium: 2 vCPU, 4 GB RAM
- t3.large: 2 vCPU, 8 GB RAM
- m5.xlarge: 4 vCPU, 16 GB RAM

**How to scale up:**
Change `instance_type` in `variables.tf`

**When to scale up:**
- Application is CPU-bound
- More memory needed per instance
- Better network performance required

### Horizontal Scaling (Scale Out)

**Current:** 2-4 instances

**Can adjust:**
```hcl
asg_min_size = 4
asg_max_size = 10
```

**Benefits:**
- Better fault tolerance
- Handles more concurrent users
- Geographic distribution (if multi-region)

**Limitations:**
- Application must be stateless
- Session data should be external (ElastiCache, DynamoDB)
- Database becomes bottleneck

### Database Scaling

**Read Scaling:**
- Add read replicas for read-heavy workloads
- Applications query replicas for reads
- Master handles writes only

**Write Scaling:**
- Optimize queries and indexes
- Use caching (ElastiCache)
- Consider database sharding (advanced)
- Upgrade instance class

---

## High Availability Analysis

### Availability Zones

**Current Setup:** 2 AZs

**Availability:**
- Single AZ failure: No impact
- Both AZs fail: Complete outage (rare)

**AWS AZ Reliability:**
- Each AZ is isolated (separate power, cooling, networking)
- Connected by low-latency links
- Historical uptime: >99.99%

### Component Redundancy

| Component | Redundancy | Single Point of Failure |
|-----------|-----------|------------------------|
| ALB | Multi-AZ | No |
| EC2 Instances | Multi-AZ, ASG | No |
| NAT Gateway | 1 per AZ | No (per AZ) |
| RDS | Multi-AZ | No |
| Internet Gateway | AWS-managed | No |

### Recovery Time Objectives (RTO)

| Failure | Detection | Recovery | Total RTO |
|---------|----------|----------|-----------|
| EC2 Instance | 30-60s | 5 min | ~6 min |
| Availability Zone | 30-60s | 0s | 1 min |
| RDS Primary | 30-60s | 60-120s | 2-3 min |

### Recovery Point Objectives (RPO)

| Component | Data Loss | RPO |
|-----------|-----------|-----|
| EC2 Instances | Stateless | 0 |
| RDS Multi-AZ | Synchronous | 0 |
| RDS Backups | Daily | 24 hours |

---

## Security Analysis

### Network Security Layers

1. **VPC Isolation:** Private network space
2. **Subnet Separation:** Public/Private/Database tiers
3. **Security Groups:** Stateful firewall at instance level
4. **NACLs:** (Not configured, but available) Stateless firewall at subnet level

### Access Control

**Principle of Least Privilege:**
- ALB: Only HTTP/HTTPS from internet
- EC2: Only HTTP from ALB, SSH from your IP
- RDS: Only MySQL from EC2

**No Public Access:**
- EC2 instances in private subnets
- RDS in database subnets (no internet route)

**IAM Roles:**
- EC2 instances use roles (not access keys)
- Credentials automatically rotated
- Scoped permissions for CloudWatch

### Data Protection

**In Transit:**
- HTTP (plain text) - Can add HTTPS
- Internal VPC traffic unencrypted (private network)
- RDS connection encrypted (configurable)

**At Rest:**
- EBS volumes unencrypted (can enable)
- RDS storage unencrypted (can enable)
- S3 buckets encrypted by default (if used)

**Recommendations for Production:**
1. Enable HTTPS on ALB (requires ACM certificate)
2. Enable RDS encryption
3. Enable EBS encryption
4. Use AWS Secrets Manager for database credentials
5. Enable VPC Flow Logs
6. Enable AWS Config for compliance

---

## Cost Optimization

### Free Tier Usage

**Eligible Resources:**
- 750 hours/month EC2 t2.micro (2 instances, 24/7)
- 750 hours/month RDS db.t3.micro
- 750 hours/month ALB
- 15 GB data transfer out

**Estimated Free Tier Coverage:** ~100% for first 12 months

### Monthly Costs (After Free Tier)

| Resource | Unit Cost | Quantity | Monthly Cost |
|----------|-----------|----------|--------------|
| EC2 t2.micro | $0.0116/hour | 2 × 730h | $16.94 |
| RDS db.t3.micro | $0.017/hour | 730h | $12.41 |
| ALB | $0.0225/hour | 730h | $16.43 |
| NAT Gateway | $0.045/hour | 2 × 730h | $65.70 |
| Data Transfer | $0.09/GB | 100 GB | $9.00 |
| **Total** | | | **~$120/month** |

### Cost Optimization Strategies

**Development/Testing:**
1. **Run during business hours only:**
   ```bash
   # Stop at 6 PM
   terraform destroy
   # Start at 9 AM
   terraform apply
   ```
   Saves 67% (16h vs 24h/day)

2. **Use single NAT Gateway:**
   Saves $32/month (not recommended for production)

3. **Remove NAT Gateways:**
   Saves $65/month (instances can't access internet)

4. **Use smaller RDS instance:**
   db.t3.micro → db.t2.micro saves $5/month

**Production:**
1. **Reserved Instances:**
   - 1-year commitment: 30-40% savings
   - 3-year commitment: 50-60% savings

2. **Savings Plans:**
   - Commit to $ amount
   - Flexible across instance types
   - 20-50% savings

3. **Spot Instances:**
   - Use for Auto Scaling Group
   - 70-90% savings
   - Risk of termination with 2-minute warning

---

## Performance Optimization

### Current Bottlenecks

1. **t2.micro CPU:** Limited compute power
2. **Single DB instance:** Write operations bottleneck
3. **GP2 storage:** Limited IOPS (100 base + 3 per GB)

### Optimization Strategies

**Application Layer:**
1. Enable caching (ElastiCache/CloudFront)
2. Optimize application code
3. Compress assets (images, CSS, JS)
4. Use CDN for static content

**Database Layer:**
1. Add read replicas for read scaling
2. Optimize queries (indexes, explain plans)
3. Use connection pooling
4. Cache frequent queries (ElastiCache)
5. Upgrade instance class if needed

**Network Layer:**
1. Enable ALB connection draining
2. Use HTTP/2 on ALB
3. Enable compression on ALB
4. Consider CloudFront CDN

---

## Disaster Recovery

### Backup Strategy

**RDS Backups:**
- Automated daily snapshots
- 7-day retention
- Point-in-time recovery
- Stored in S3 (multiple AZs)

**Manual Snapshots:**
```bash
aws rds create-db-snapshot \
  --db-instance-identifier scalable-web-app-db \
  --db-snapshot-identifier manual-backup-YYYY-MM-DD
```

### Recovery Procedures

**Complete Rebuild:**
```bash
# From Terraform
terraform apply

# Database will be empty
# Restore from snapshot if needed
```

**Database Restore:**
```bash
# Create new RDS from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier restored-db \
  --db-snapshot-identifier snapshot-name

# Update Terraform state
terraform import aws_db_instance.main restored-db
```

### Cross-Region DR

**For production:**
1. Enable RDS cross-region replication
2. Use S3 cross-region replication for assets
3. Maintain Terraform code in version control
4. Document recovery procedures
5. Test recovery process regularly

---

## Compliance and Governance

### AWS Well-Architected Framework

**Operational Excellence:**
- ✅ Infrastructure as Code (Terraform)
- ✅ CloudWatch monitoring
- ❌ Need automated testing
- ❌ Need runbooks for incidents

**Security:**
- ✅ Network isolation (VPC, subnets)
- ✅ Security groups with least privilege
- ✅ IAM roles (no access keys)
- ⚠️ Should enable encryption at rest
- ⚠️ Should use HTTPS
- ❌ Need AWS Config for compliance

**Reliability:**
- ✅ Multi-AZ deployment
- ✅ Auto Scaling
- ✅ Load balancing
- ✅ Health checks
- ✅ Automated backups

**Performance Efficiency:**
- ✅ Right-sized instances (for learning)
- ✅ Auto Scaling
- ❌ No caching layer
- ❌ No CDN for static content

**Cost Optimization:**
- ✅ Using Free Tier eligible resources
- ✅ Auto Scaling (pay for what you use)
- ⚠️ Could use Spot Instances
- ⚠️ Could use Reserved Instances (production)

**Sustainability:**
- ✅ Using latest instance types (t3)
- ✅ Auto Scaling (no waste)
- ⚠️ Could optimize data transfer

---

## Future Enhancements

### Phase 1: Security Improvements
1. Add HTTPS/SSL certificate
2. Enable RDS encryption
3. Enable EBS encryption
4. Use AWS Secrets Manager for credentials
5. Add WAF to ALB
6. Enable GuardDuty

### Phase 2: Performance
1. Add ElastiCache for session/data caching
2. Add CloudFront CDN
3. Add RDS read replicas
4. Upgrade to GP3 storage
5. Enable enhanced monitoring

### Phase 3: Observability
1. Implement distributed tracing (X-Ray)
2. Add custom CloudWatch metrics
3. Set up CloudWatch Insights
4. Implement application logging
5. Add APM tool (New Relic, Datadog)

### Phase 4: Automation
1. Add CI/CD pipeline (CodePipeline)
2. Automated testing
3. Blue-green deployments
4. Canary deployments
5. Automated rollbacks

### Phase 5: Advanced Features
1. Multi-region deployment
2. Database sharding
3. Microservices architecture
4. Kubernetes (EKS)
5. Serverless components (Lambda)

---

## Conclusion

This architecture demonstrates AWS best practices for a scalable, highly available web application. Key strengths:

1. **High Availability:** Multi-AZ deployment across all layers
2. **Scalability:** Auto Scaling handles traffic variations
3. **Security:** Defense-in-depth with multiple security layers
4. **Cost-Effective:** Uses Free Tier eligible resources
5. **Maintainable:** Infrastructure as Code with Terraform

The architecture is production-ready with minor enhancements (HTTPS, encryption) and provides an excellent foundation for AWS Solutions Architect certification.

---

**Questions for Further Learning:**

1. What happens if both NAT Gateways fail simultaneously?
2. How would you implement HTTPS on the ALB?
3. How would you handle session state in a scaled environment?
4. What metrics would you add for better observability?
5. How would you implement a blue-green deployment?
6. What would change for a microservices architecture?
7. How would you handle database schema migrations?
8. What's the impact of removing Multi-AZ from RDS?
9. How would you implement disaster recovery in another region?
10. What's the maximum traffic this architecture can handle?