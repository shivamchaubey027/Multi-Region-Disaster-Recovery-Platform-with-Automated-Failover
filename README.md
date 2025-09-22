# Multi-Region Infrastructure Foundation for Disaster Recovery on AWS

## Objective
This project shows how to design and build a resilient, multi-region AWS infrastructure using **Terraform**.  
The setup follows a **Warm Standby (Active-Passive)** model, acting as the base layer for a proper Disaster Recovery (DR) platform.

Main goal:  
- Handle local failures with **Multi-AZ** high availability.  
- Stay safe against full regional outages with a **cross-region replica**.

---

## Key Features & Concepts

### 1. Infrastructure as Code (IaC)
- Everything is defined in Terraform → repeatable, version-controlled, and automated.  
- Each region (us-east-1, eu-north-1) has its own isolated state, which is the right way to handle multi-env setups.

---

### 2. Networking & Security
- **Multi-Region VPCs** → Two VPCs with non-overlapping CIDRs (10.0.0.0/17 and 10.0.128.0/17).  
- **High Availability** → Public + private subnets in multiple AZs, so even if one data center dies, services keep running.  
- **Cross-Region Connectivity** → VPC Peering gives private, low-latency comms between regions using AWS’s global backbone.  
- **Principle of Least Privilege** → Security groups are locked down. Example: DB is only accessible from the app server SG, never from the internet.  

---

### 3. Database & Data Resiliency
- **Multi-AZ RDS PostgreSQL** → Synchronous replication + auto-failover for local HA (Low RTO / Zero RPO).  
- **Cross-Region Read Replica** → In eu-north-1 for DR, keeping data ready to be promoted when needed (Low RPO for regional outage).  
- **Consistency Tradeoff** →  
  - Multi-AZ = Strong Consistency (CP).  
  - Cross-Region Replica = Eventual Consistency (AP).  

---

## Tech Stack
- **Cloud**: AWS  
- **IaC**: Terraform  
- **Compute**: EC2  
- **Database**: RDS for PostgreSQL (Multi-AZ + Cross-Region Replica)  
- **Networking**: VPC, Subnets, Route Tables, IGW, VPC Peering  
- **Security**: IAM, Security Groups  

---

## How to Run
1. Clone this repo.  
2. Configure AWS credentials.  
3. Go into `us-east-1/` folder.  
   - Run `terraform init` → `terraform apply`.  
4. Go into `eu-north-1/` folder.  
   - Update `replicate_source_db` ARN + `vpc_peering_connection_id` using outputs from the us-east-1 deploy.  
   - Run `terraform init` → `terraform apply`.  

---

## Future Work
This project sets up the foundation. Next steps would be adding automation:  

- **Automated Failover** → CloudWatch Alarm → Lambda → promote the read replica.  
- **Automated Backups** → Lambda to copy RDS snapshots to DR region.  
