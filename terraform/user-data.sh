#!/bin/bash

# This script runs on instance launch to set up the web server

set -e  # Exit on any error

# Update system packages
yum update -y

# Install Apache web server
yum install -y httpd

# Install MySQL client for database connectivity testing
yum install -y mysql

# Start and enable Apache
systemctl start httpd
systemctl enable httpd

# Get instance metadata
INSTANCE_ID=$(ec2-metadata --instance-id | cut -d " " -f 2)
AVAILABILITY_ZONE=$(ec2-metadata --availability-zone | cut -d " " -f 2)
PRIVATE_IP=$(ec2-metadata --local-ipv4 | cut -d " " -f 2)

# Create a simple Hello World page with instance information
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Scalable Web Application - AWS Project</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 20px;
        }
        
        .container {
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
            padding: 50px;
            max-width: 800px;
            width: 100%;
            animation: fadeIn 0.8s ease-in;
        }
        
        @keyframes fadeIn {
            from {
                opacity: 0;
                transform: translateY(20px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }
        
        h1 {
            color: #333;
            margin-bottom: 20px;
            font-size: 2.5em;
            text-align: center;
        }
        
        .status {
            background: #10b981;
            color: white;
            padding: 15px 30px;
            border-radius: 50px;
            display: inline-block;
            font-weight: bold;
            margin-bottom: 30px;
            animation: pulse 2s infinite;
        }
        
        @keyframes pulse {
            0%, 100% {
                transform: scale(1);
            }
            50% {
                transform: scale(1.05);
            }
        }
        
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-top: 30px;
        }
        
        .info-card {
            background: #f8fafc;
            padding: 20px;
            border-radius: 10px;
            border-left: 4px solid #667eea;
        }
        
        .info-card h3 {
            color: #667eea;
            margin-bottom: 10px;
            font-size: 0.9em;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .info-card p {
            color: #333;
            font-size: 1.1em;
            font-weight: 600;
            word-break: break-all;
        }
        
        .features {
            margin-top: 40px;
            padding-top: 40px;
            border-top: 2px solid #e5e7eb;
        }
        
        .features h2 {
            color: #333;
            margin-bottom: 20px;
            text-align: center;
        }
        
        .features ul {
            list-style: none;
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
        }
        
        .features li {
            padding: 15px;
            background: #f0f9ff;
            border-radius: 8px;
            color: #333;
        }
        
        .features li:before {
            content: "✓ ";
            color: #10b981;
            font-weight: bold;
            margin-right: 8px;
        }
        
        .footer {
            margin-top: 40px;
            text-align: center;
            color: #666;
            font-size: 0.9em;
        }
        
        .aws-logo {
            text-align: center;
            margin-bottom: 20px;
        }
        
        .aws-logo span {
            background: #ff9900;
            color: white;
            padding: 10px 20px;
            border-radius: 5px;
            font-weight: bold;
            font-size: 1.2em;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="aws-logo">
            <span>AWS ☁️</span>
        </div>
        
        <h1>🎉 Hello World!</h1>
        
        <center>
            <div class="status">✓ Application Running Successfully</div>
        </center>
        
        <div class="info-grid">
            <div class="info-card">
                <h3>Instance ID</h3>
                <p>INSTANCE_ID_PLACEHOLDER</p>
            </div>
            <div class="info-card">
                <h3>Availability Zone</h3>
                <p>AZ_PLACEHOLDER</p>
            </div>
            <div class="info-card">
                <h3>Private IP</h3>
                <p>IP_PLACEHOLDER</p>
            </div>
            <div class="info-card">
                <h3>Database Status</h3>
                <p>DB_STATUS_PLACEHOLDER</p>
            </div>
        </div>
        
        <div class="features">
            <h2>🏗️ Architecture Features</h2>
            <ul>
                <li>Auto Scaling Group</li>
                <li>Application Load Balancer</li>
                <li>Multi-AZ Deployment</li>
                <li>RDS MySQL Database</li>
                <li>CloudWatch Monitoring</li>
                <li>High Availability</li>
                <li>Fault Tolerance</li>
                <li>Cost Optimized</li>
            </ul>
        </div>
        
        <div class="footer">
            <p><strong>AWS Solutions Architect - Associate</strong></p>
            <p>Graduation Project: Scalable Web Application</p>
            <p>Infrastructure as Code with Terraform</p>
        </div>
    </div>
</body>
</html>
EOF

# Replace placeholders with actual values
sed -i "s/INSTANCE_ID_PLACEHOLDER/$INSTANCE_ID/g" /var/www/html/index.html
sed -i "s/AZ_PLACEHOLDER/$AVAILABILITY_ZONE/g" /var/www/html/index.html
sed -i "s/IP_PLACEHOLDER/$PRIVATE_IP/g" /var/www/html/index.html

# Test database connectivity
DB_ENDPOINT="${db_endpoint}"
DB_NAME="${db_name}"
DB_USER="${db_username}"
DB_PASS="${db_password}"

# Remove port from endpoint if present
DB_HOST=$(echo $DB_ENDPOINT | cut -d: -f1)

# Try to connect to database
if mysql -h $DB_HOST -u $DB_USER -p$DB_PASS -e "SELECT 1;" &>/dev/null; then
    DB_STATUS="✓ Connected"
else
    DB_STATUS="⚠ Pending"
fi

sed -i "s/DB_STATUS_PLACEHOLDER/$DB_STATUS/g" /var/www/html/index.html

# Create a health check endpoint
echo "OK" > /var/www/html/health.html

# Set proper permissions
chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html

# Configure Apache for better performance
cat >> /etc/httpd/conf/httpd.conf << 'EOF'

# Performance tuning
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 5

# Enable compression
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css text/javascript application/javascript
</IfModule>
EOF

# Restart Apache to apply changes
systemctl restart httpd

# Install CloudWatch agent for enhanced monitoring (optional)
# wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
# rpm -U ./amazon-cloudwatch-agent.rpm

# Log completion
echo "User data script completed successfully at $(date)" >> /var/log/user-data.log