#!/bin/bash

mkdir -p /opt/system-monitor

python3 -m venv /opt/system-monitor/venu
source /opt/system-monitor/venu/bin/activate
pip install --upgrade pip && pip install psutil requests pytz


cat <<EOF > /opt/system-monitor/config.json
{
    "email_sender": "babafarooq001@gmail.com",
    "email_receivers": ["babathaher786@gmail.com", "babafarooq9154@gmail.com"],
    "smtp_server": "smtp.gmail.com",
    "smtp_port": 587,
    "smtp_username": "babafarooq001@gmail.com",
    "smtp_password": "hulu pver rsvv rmpk",
    "time_zone": "Asia/Kolkata",
    "threshold_disk": 7,
    "threshold_memory": 10,
    "threshold_cpu": 90,
    "check_interval": 60,
    "email_cooldown": 3600
}
EOF

cat <<EOF > /opt/system-monitor/system_monitor.py
import smtplib
import subprocess
import psutil
import socket
import json
import requests
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.image import MIMEImage
from datetime import datetime, timedelta
import pytz
import os
import time

# Load configuration from JSON file
config_file = '/opt/smtp/config.json'
if not os.path.exists(config_file):
    raise FileNotFoundError(f"Configuration file {config_file} not found")

with open(config_file, 'r') as f:
    config = json.load(f)

# SMTP Configuration from config
email_sender = config['email_sender']
email_receivers = config['email_receivers']
smtp_server = config['smtp_server']
smtp_port = config['smtp_port']
smtp_username = config['smtp_username']
smtp_password = config['smtp_password']
logo_url = 'https://oneplatform.blusapphire.com/images/logos/oneplatform-login_icon.png'

# Threshold Configuration from config
try:
    threshold_disk = float(config['threshold_disk'])
    threshold_memory = float(config['threshold_memory'])
    threshold_cpu = float(config['threshold_cpu'])
    check_interval = float(config['check_interval'])
    email_cooldown = float(config['email_cooldown'])
    include_uptime = config.get('include_uptime', True)  # Default to True if not specified
    # Validate thresholds and intervals
    for thresh, name in [(threshold_disk, 'threshold_disk'), (threshold_memory, 'threshold_memory'), (threshold_cpu, 'threshold_cpu')]:
        if not 0 <= thresh <= 100:
            raise ValueError(f"{name} must be between 0 and 100, got {thresh}")
    if check_interval <= 0:
        raise ValueError(f"check_interval must be positive, got {check_interval}")
    if email_cooldown <= 0:
        raise ValueError(f"email_cooldown must be positive, got {email_cooldown}")
    if not isinstance(include_uptime, bool):
        raise ValueError(f"include_uptime must be a boolean, got {include_uptime}")
except KeyError as e:
    raise KeyError(f"Missing required key in config.json: {e}")
except ValueError as e:
    raise ValueError(f"Invalid value in config.json: {e}")

# Time zone from config
time_zone = config['time_zone']
try:
    tz = pytz.timezone(time_zone)
except pytz.exceptions.UnknownTimeZoneError:
    raise ValueError(f"Invalid time zone specified in config: {time_zone}")

# Email subjects
resource_subject = f'System Resource Alert for {socket.gethostname()}'
down_subject = f'System Online Notification for {socket.gethostname()}'

# Track last email sent time and reboot notification status
last_email_time = None
reboot_notified = False  # Track if reboot notification has been sent

def get_disk_usage():
    """Return the disk usage percentage of the root filesystem."""
    disk_usage = psutil.disk_usage('/')
    return disk_usage.percent

def get_memory_usage():
    """Return memory usage details."""
    memory_info = psutil.virtual_memory()
    return memory_info.total, memory_info.available, memory_info.used, memory_info.percent

def get_cpu_usage():
    """Return CPU usage details and average usage across all cores."""
    cpu_percentages = psutil.cpu_percent(percpu=True)
    avg_cpu_usage = sum(cpu_percentages) / len(cpu_percentages) if cpu_percentages else 0
    return cpu_percentages, avg_cpu_usage

def get_df_output():
    """Run 'df -h' command and return its output."""
    result = subprocess.run(['df', '-h'], capture_output=True, text=True)
    return result.stdout

def get_uptime():
    """Return the system uptime in a formatted string for HTML display and raw seconds."""
    try:
        result = subprocess.run(['uptime', '-p'], capture_output=True, text=True)
        uptime_str = result.stdout.strip()
        # Get raw uptime in seconds
        boot_time = psutil.boot_time()
        current_time = time.time()
        uptime_seconds = current_time - boot_time
        # Parse uptime for display
        parts = uptime_str.replace('up ', '').split(', ')
        formatted_parts = []
        for part in parts:
            if 'day' in part or 'hour' in part or 'minute' in part:
                formatted_parts.append(part)
        if not formatted_parts:
            return "Uptime: less than a minute", uptime_seconds
        return f"Uptime: {', '.join(formatted_parts)}", uptime_seconds
    except Exception as e:
        print(f"Failed to get uptime: {e}")
        return "Uptime: unavailable", 0

def get_last_power_off_time():
    """Estimate the last power-off time based on current time and uptime."""
    try:
        boot_time = psutil.boot_time()
        boot_time_dt = datetime.fromtimestamp(boot_time, tz=tz)
        # Assume power-off was just before boot
        power_off_time = boot_time_dt - timedelta(seconds=1)
        return power_off_time.strftime('%I:%M %p %Z on %A, %B %d, %Y')
    except Exception as e:
        print(f"Failed to get last power-off time: {e}")
        return "Last Power-Off: unavailable"

def format_cpu_usage(cpu_percentages):
    """Format CPU usage as HTML table rows."""
    rows = ""
    for i, percent in enumerate(cpu_percentages):
        rows += f"""
        <tr>
            <td>CPU Core {i}</td>
            <td>{percent}%</td>
        </tr>
        """
    return rows

def format_memory_usage(total, available, used, percent):
    """Format memory usage as HTML table row."""
    return f"""
    <tr>
        <td>{format_size(total)}</td>
        <td>{format_size(available)}</td>
        <td>{format_size(used)}</td>
        <td>{percent}%</td>
    </tr>
    """

def format_df_output(df_output):
    """Format df -h output as HTML table rows."""
    lines = df_output.splitlines()
    html_rows = ""

    for line in lines[1:]:
        columns = line.split()
        if columns:
            html_rows += "<tr>"
            for column in columns:
                html_rows += f"<td>{column}</td>"
            html_rows += "</tr>"

    return html_rows

def format_size(bytes_size):
    """Format size in human-readable format."""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_size < 1024:
            return f"{bytes_size:.2f} {unit}"
        bytes_size /= 1024
    return f"{bytes_size:.2f} TB"

def send_email(subject, body):
    """Send an email with the given subject and body."""
    global last_email_time
    msg = MIMEMultipart()
    msg['From'] = email_sender
    msg['Subject'] = subject

    # Attach the body with HTML content
    msg.attach(MIMEText(body, 'html'))

    # Fetch and attach the logo image from URL
    try:
        response = requests.get(logo_url, timeout=10)
        response.raise_for_status()
        logo = MIMEImage(response.content)
        logo.add_header('Content-ID', '<logo.png>')
        msg.attach(logo)
    except requests.RequestException as e:
        print(f"Failed to fetch logo from {logo_url}: {e}")
        # Continue without logo if fetching fails
        pass

    try:
        with smtplib.SMTP(smtp_server, smtp_port) as server:
            server.starttls()
            server.login(smtp_username, smtp_password)

            for receiver in email_receivers:
                server.sendmail(email_sender, receiver, msg.as_string())

        print("Email sent successfully to all recipients!")
        last_email_time = time.time()  # Update last email time
        return True
    except Exception as e:
        print(f"Failed to send email: {e}")
        return False

def main():
    """Check system resource usage and reboot status periodically, sending alerts if thresholds are exceeded or reboot detected."""
    global last_email_time, reboot_notified
    while True:
        # Get current time in configured time zone
        current_time = datetime.now(tz).strftime('%I:%M %p %Z on %A, %B %d, %Y')

        # Get system metrics
        disk_usage = get_disk_usage()
        memory_total, memory_available, memory_used, memory_percent = get_memory_usage()
        cpu_percentages, avg_cpu_usage = get_cpu_usage()
        uptime_str, uptime_seconds = get_uptime() if include_uptime else ("Uptime: disabled", 0)

        # Check for recent reboot (uptime < 30 seconds)
        if uptime_seconds < 30 and not reboot_notified:
            # Prepare reboot notification email
            last_power_off = get_last_power_off_time()
            alert_message = [
                "System Online Alerts",
                uptime_str,
                f"CPU usage is high: {avg_cpu_usage:.1f}% (average across all cores)",
                f"Memory usage is high: {memory_percent}%",
                f"Disk usage is high: {disk_usage}%",
                f"System Online at {last_power_off}"
            ]

            # Read the HTML template
            with open('/opt/smtp/source.html', 'r') as file:
                html_template = file.read()

            # Format data for tables
            cpu_html_rows = format_cpu_usage(cpu_percentages)
            memory_html_row = format_memory_usage(memory_total, memory_available, memory_used, memory_percent)
            df_html_rows = format_df_output(get_df_output())

            # Insert the formatted table rows
            email_body = html_template
            email_body = email_body.replace("<!-- Data rows for CPU usage will be inserted here -->", cpu_html_rows)
            email_body = email_body.replace("<!-- Data rows for memory usage will be inserted here -->", memory_html_row)
            email_body = email_body.replace("<!-- Data rows for disk usage will be inserted here -->", df_html_rows)

            # Add alert messages and sending time
            email_body = f"""
            <h2>System Online Notification</h2>
            <p>Sending time: {current_time}</p>
            <h3>System Alerts</h3>
            <p>{"<br>".join(alert_message)}</p><br>
            {email_body}
            """

            # Send the reboot notification email
            if last_email_time is None or (time.time() - last_email_time) >= email_cooldown:
                send_email(down_subject, email_body)
                reboot_notified = True  # Prevent further reboot notifications until next reboot
            else:
                print(f"Reboot detected at {current_time}, but email skipped due to cooldown. Next email possible in {int(email_cooldown - (time.time() - last_email_time))} seconds.")

        # Regular resource monitoring
        alert_message = []
        include_cpu_usage = False
        include_memory_usage = False
        include_disk_usage = False

        if include_uptime:
            alert_message.append(uptime_str)

        if avg_cpu_usage > threshold_cpu:
            alert_message.append(f"CPU usage is high: {avg_cpu_usage:.1f}% (average across all cores)")
            include_cpu_usage = True

        if memory_percent > threshold_memory:
            alert_message.append(f"Memory usage is high: {memory_percent}%")
            include_memory_usage = True

        if disk_usage > threshold_disk:
            alert_message.append(f"Disk usage is high: {disk_usage}%")
            include_disk_usage = True

        # Send resource alert email if thresholds are exceeded
        if len(alert_message) > (1 if include_uptime else 0):
            current_time_seconds = time.time()
            if last_email_time is None or (current_time_seconds - last_email_time) >= email_cooldown:
                # Read the HTML template
                with open('/opt/smtp/source.html', 'r') as file:
                    html_template = file.read()

                # Format data for tables that need to be included
                cpu_html_rows = format_cpu_usage(cpu_percentages) if include_cpu_usage else ""
                memory_html_row = format_memory_usage(memory_total, memory_available, memory_used, memory_percent) if include_memory_usage else ""
                df_html_rows = format_df_output(get_df_output()) if include_disk_usage else ""

                # Remove sections from HTML template if not needed
                email_body = html_template
                if not include_cpu_usage:
                    email_body = email_body.replace(
                        "<!-- CPU Usage Table -->\n    <h3>CPU Usage</h3>\n    <table>\n        <tr>\n            <th>CPU Core</th>\n            <th>Usage %</th>\n        </tr>\n        <!-- Data rows for CPU usage will be inserted here -->\n    </table>",
                        ""
                    )
                if not include_memory_usage:
                    email_body = email_body.replace(
                        "<!-- Memory Usage Table -->\n    <h3>Memory Usage</h3>\n    <table>\n        <tr>\n            <th>Total</th>\n            <th>Available</th>\n            <th>Used</th>\n            <th>Percentage Used</th>\n        </tr>\n        <!-- Data rows for memory usage will be inserted here -->\n    </table>",
                        ""
                    )
                if not include_disk_usage:
                    email_body = email_body.replace(
                        "<!-- Disk Usage Table -->\n    <h3>Disk Usage</h3>\n    <table>\n        <tr>\n            <th>Filesystem</th>\n            <th>Size</th>\n            <th>Used</th>\n            <th>Avail</th>\n            <th>Use%</th>\n            <th>Mounted on</th>\n        </tr>\n        <!-- Data rows for disk usage will be inserted here -->\n    </table>",
                        ""
                    )

                # Insert the formatted table rows
                email_body = email_body.replace("<!-- Data rows for CPU usage will be inserted here -->", cpu_html_rows)
                email_body = email_body.replace("<!-- Data rows for memory usage will be inserted here -->", memory_html_row)
                email_body = email_body.replace("<!-- Data rows for disk usage will be inserted here -->", df_html_rows)

                # Add alert messages and sending time
                email_body = f"""
                <h2>System Resource Report</h2>
                <p>Sending time: {current_time}</p>
                <h3>System Alerts</h3>
                <p>{"<br>".join(alert_message)}</p><br>
                {email_body}
                """

                # Send the resource alert email
                send_email(resource_subject, email_body)
            else:
                print(f"Alerts triggered at {current_time}, but email skipped due to cooldown. Next email possible in {int(email_cooldown - (current_time_seconds - last_email_time))} seconds.")

        else:
            print(f"No resource alerts triggered at {current_time}. {uptime_str if include_uptime else ''} Checking again in {check_interval} seconds.")

        # Reset reboot_notified if uptime exceeds 30 seconds (allows detection of future reboots)
        if uptime_seconds >= 30:
            reboot_notified = False

        # Wait before the next check
        time.sleep(check_interval)

if __name__ == "__main__":
    main()
EOF


cat <<EOF > /opt/system-monitor/source.html
<!DOCTYPE html>
<html>
<head>
    <style>
        body {
            font-family: Arial, sans-serif;
            color: #333;
            background-color: #f4f6f7; /* Light background color */
            padding: 20px;
        }
        h2 {
            color: #2c3e50;
            border-bottom: 2px solid #2c3e50;
            padding-bottom: 10px;
        }
        h3 {
            color: #2c3e50;
            border-bottom: 1px solid #dfe6e9;
            padding-bottom: 5px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 12px;
            margin-top: 20px;
            background-color: #fff;
            border-radius: 5px; /* Rounded corners */
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1); /* Subtle shadow */
        }
        th, td {
            border: 1px solid #dfe6e9;
            padding: 8px;
            text-align: left;
        }
        th {
            background-color: #3498db;
            color: #fff;
        }
        .signature {
            margin-top: 30px;
            font-size: 14px;
            color: #2c3e50;
            text-align: left;
            line-height: 1.6;
        }
        .signature img {
            display: block;
            margin-bottom: 10px;
            height: 60px;
        }
        .signature p {
            margin: 0;
        }
        .signature strong {
            font-weight: bold;
        }
        .contact-info a {
            color: #3498db;
            text-decoration: none;
        }
        .footer {
            margin-top: 40px;
            font-size: 10px;
            color: #7f8c8d;
            text-align: center;
        }
        .notice {
            font-size: 12px;
            color: #e74c3c;
            margin-top: 20px;
            text-align: center;
        }
    </style>
</head>
<body>
    <h2>💡System Resource Report</h2>

    <!-- CPU Usage Table -->
    <h3>CPU Usage</h3>
    <table>
        <tr>
            <th>CPU Core</th>
            <th>Usage %</th>
        </tr>
        <!-- Data rows for CPU usage will be inserted here -->
    </table>

    <!-- Memory Usage Table -->
    <h3>Memory Usage</h3>
    <table>
        <tr>
            <th>Total</th>
            <th>Available</th>
            <th>Used</th>
            <th>Percentage Used</th>
        </tr>
        <!-- Data rows for memory usage will be inserted here -->
    </table>

    <!-- Disk Usage Table -->
    <h3>Disk Usage</h3>
    <table>
        <tr>
            <th>Filesystem</th>
            <th>Size</th>
            <th>Used</th>
            <th>Avail</th>
            <th>Use%</th>
            <th>Mounted on</th>
        </tr>
        <!-- Data rows for disk usage will be inserted here -->
    </table>

    <div class="signature">
        <p>Thanks & Regards,</p>
        <img src="cid:logo.png" alt="Company Logo">
        <p>
            <strong>Baba Farooq SN</strong>,<br>
            Sr Technical Support Engineer,<br>
            Snb-Tech Cyber Solutions,<br>
            Contact No: <a href="tel:+918142566154">+91 8142566154</a>,<br>
            Contact Email: <a href="mailto:babafarooq001@gmail.com">babafarooq001@gmail.com</a>,<br>
            Official Website: <a href="http://snb-tech.sytes.net" target="_blank">http://snb-tech.sytes.net</a>
        </p>
    </div>

    <div class="notice">
        <p>Notice: This email is intended solely for the purpose of sending system health reports. Please do not reply to this email...!</p>
    </div>

    <div class="footer">
        <p>Confidentiality Notice: This email and any attachments are confidential. If you are not the intended recipient, please notify the sender and delete this email immediately.</p>
    </div>
</body>
</html>
EOF


cat <<EOF > /opt/system-monitor/run_monitor.sh
#!/bin/bash

PYTHON="/opt/system-monitor/venu/bin/python3"
SCRIPT="/opt/system-monitor/system_monitor.py"
PIDFILE="/var/run/system_monitor.pid"

# Check if Python and script exist
[ ! -x "$PYTHON" ] && { echo "Error: Python not found at $PYTHON" >&2; exit 1; }
[ ! -f "$SCRIPT" ] && { echo "Error: Script not found at $SCRIPT" >&2; exit 1; }

# Check if process is running
if pgrep -f "$PYTHON $SCRIPT" > /dev/null; then
    echo "Process already running. Exiting."
    exit 0
fi

# Start script in background and save PID
echo "Starting $SCRIPT..."
"$PYTHON" "$SCRIPT" >/dev/null 2>&1 &
PID=$!
echo $PID > "$PIDFILE"

# Verify process started
sleep 1
if ps -p $PID > /dev/null; then
    echo "Script started successfully (PID: $PID)."
    exit 0
else
    echo "Error: Failed to start $SCRIPT" >&2
    rm -f "$PIDFILE"
    exit 1
fi
EOF

chmod +x /opt/system-monitor/run_monitor.sh

(crontab -l 2>/dev/null; echo "* * * * * /opt/system-monitor/run_monitor.sh") | crontab -

