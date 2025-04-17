import smtplib
import subprocess
import psutil
import os
import json
from datetime import datetime, time, timedelta
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.image import MIMEImage

# Threshold Configuration
threshold_disk = 10  # Disk usage percentage threshold
threshold_memory = 10  # Memory usage percentage threshold
threshold_cpu = 10  # CPU usage percentage threshold

# Paths to monitor for disk usage
paths_to_monitor = ['/', '/opt', '/var', '/etc']

# SMTP Configuration
email_sender = 'babafarooq001@gmail.com'
email_receivers = ['babathaher786@gmail.com', 'babafarooq9154@gmail.com', 'royalgreen3367@gmail.com']
email_alert_subject = 'System Resource Alert for babafarooq-s1'
email_report_subject = 'Daily System Health Report for babafarooq-s1'
smtp_server = 'smtp.gmail.com'
smtp_port = 587
smtp_username = 'babafarooq001@gmail.com'
smtp_password = 'glor fuby gbus rcal'  # Replace with environment variable in production
logo_path = '/opt/snb-tech/Alpha-Smtp/logo.png'
html_template_path = '/opt/snb-tech/Alpha-Smtp/source.html'
last_report_file = '/opt/snb-tech/Alpha-Smtp/last_report.json'

# Time windows for reports (7:50 AM and 8:40 PM)
REPORT_TIMES = [
    time(7, 50),  # 7:50 AM
    time(20, 40)  # 8:40 PM
]
WINDOW_MINUTES = 5  # 5-minute window for scheduling

def get_disk_usage(path):
    """Return the disk usage percentage for the specified path."""
    try:
        disk_usage = psutil.disk_usage(path)
        return disk_usage.percent
    except OSError as e:
        print(f"Error accessing path {path}: {e}")
        return None

def get_memory_usage():
    """Return memory usage details."""
    memory_info = psutil.virtual_memory()
    return memory_info.total, memory_info.available, memory_info.used, memory_info.percent

def get_cpu_usage():
    """Return CPU usage details."""
    cpu_percentages = psutil.cpu_percent(percpu=True, interval=1)
    return cpu_percentages

def get_df_output():
    """Run 'df -h' command and return its output."""
    try:
        result = subprocess.run(['df', '-h'], capture_output=True, text=True, check=True)
        return result.stdout
    except subprocess.CalledProcessError as e:
        print(f"Failed to run df -h: {e}")
        return ""

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

def format_disk_usage_report():
    """Format disk usage for all monitored paths as HTML."""
    rows = ""
    for path in paths_to_monitor:
        usage = get_disk_usage(path)
        if usage is not None:
            rows += f"""
            <tr>
                <td>{path}</td>
                <td>{usage}%</td>
            </tr>
            """
    return rows

def format_size(bytes_size):
    """Format size in human-readable format."""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_size < 1024:
            return f"{bytes_size:.2f} {unit}"
        bytes_size /= 1024
    return f"{bytes_size:.2f} TB"

def send_email(subject, body):
    """Send an email with the given subject and body."""
    msg = MIMEMultipart()
    msg['From'] = email_sender
    msg['Subject'] = subject
    msg['To'] = ', '.join(email_receivers)

    # Attach the body with HTML content
    msg.attach(MIMEText(body, 'html'))

    # Attach the logo image
    try:
        with open(logo_path, 'rb') as img:
            logo = MIMEImage(img.read())
            logo.add_header('Content-ID', '<logo.png>')
            msg.attach(logo)
    except FileNotFoundError:
        print(f"Logo file not found at {logo_path}")
    except PermissionError:
        print(f"Permission denied accessing logo file at {logo_path}")

    try:
        with smtplib.SMTP(smtp_server, smtp_port) as server:
            server.starttls()
            server.login(smtp_username, smtp_password)
            server.sendmail(email_sender, email_receivers, msg.as_string())
        print(f"Email sent successfully: {subject}")
    except smtplib.SMTPAuthenticationError:
        print("SMTP authentication failed")
    except smtplib.SMTPConnectError:
        print("Failed to connect to SMTP server")
    except Exception as e:
        print(f"Unexpected error while sending email: {e}")

def read_last_report_times():
    """Read the timestamps of the last health reports."""
    try:
        with open(last_report_file, 'r') as f:
            data = json.load(f)
            return data.get('am', '1970-01-01'), data.get('pm', '1970-01-01')
    except (FileNotFoundError, json.JSONDecodeError):
        return '1970-01-01', '1970-01-01'

def write_last_report_time(slot):
    """Write the current date as the last report time for the given slot (am/pm)."""
    current_date = datetime.now().strftime('%Y-%m-%d')
    data = {}
    try:
        with open(last_report_file, 'r') as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        pass

    data[slot] = current_date
    try:
        with open(last_report_file, 'w') as f:
            json.dump(data, f)
    except PermissionError:
        print(f"Permission denied writing to {last_report_file}")
    except Exception as e:
        print(f"Error writing to {last_report_file}: {e}")

def is_report_time():
    """Check if current time is within the report window (7:50 AM or 8:40 PM)."""
    now = datetime.now()
    current_time = now.time()
    current_date = now.strftime('%Y-%m-%d')
    last_am_date, last_pm_date = read_last_report_times()

    for report_time in REPORT_TIMES:
        # Calculate time window (e.g., 7:50 AM ± 5 minutes)
        start_time = (datetime.combine(now.date(), report_time) - 
                     timedelta(minutes=WINDOW_MINUTES)).time()
        end_time = (datetime.combine(now.date(), report_time) + 
                   timedelta(minutes=WINDOW_MINUTES)).time()

        # Check if current time is within the window
        if start_time <= current_time <= end_time:
            slot = 'am' if report_time.hour < 12 else 'pm'
            last_report_date = last_am_date if slot == 'am' else last_pm_date
            # Only send report if it hasn't been sent today for this slot
            if last_report_date != current_date:
                return True, slot
    return False, None

def send_health_report(slot):
    """Generate and send a daily system health report."""
    # Get system metrics
    memory_total, memory_available, memory_used, memory_percent = get_memory_usage()
    cpu_percentages = get_cpu_usage()
    df_output = get_df_output()

    # Format data for report
    memory_html_row = format_memory_usage(memory_total, memory_available, memory_used, memory_percent)
    cpu_html_rows = format_cpu_usage(cpu_percentages)
    df_html_rows = format_df_output(df_output)
    disk_html_rows = format_disk_usage_report()

    # Read the HTML template
    try:
        with open(html_template_path, 'r') as file:
            html_template = file.read()
    except FileNotFoundError:
        print(f"HTML template file not found at {html_template_path}")
        return
    except PermissionError:
        print(f"Permission denied accessing HTML template file at {html_template_path}")
        return

    # Modify template for report
    email_body = html_template.replace("<!-- Data rows for CPU usage will be inserted here -->", cpu_html_rows)
    email_body = email_body.replace("<!-- Data rows for memory usage will be inserted here -->", memory_html_row)
    email_body = email_body.replace("<!-- Data rows for disk usage will be inserted here -->", df_html_rows)
    
    # Add disk usage report table
    disk_report_table = f"""
    <h2>Disk Usage Report</h2>
    <table border="1">
        <tr>
            <th>Path</th>
            <th>Usage (%)</th>
        </tr>
        {disk_html_rows}
    </table>
    <br><br>
    """
    email_body = "<h2>Daily System Health Report</h2>" + disk_report_table + email_body

    # Send the report and update last report time
    send_email(email_report_subject, email_body)
    write_last_report_time(slot)

def main():
    """Check system resource usage and send alerts or health report as needed."""
    alert_message = []
    include_memory_usage = False
    include_df_output = False
    include_cpu_usage = False

    # Check disk usage for each path
    for path in paths_to_monitor:
        disk_usage = get_disk_usage(path)
        if disk_usage is not None and disk_usage > threshold_disk:
            alert_message.append(f"Disk usage for {path} is high: {disk_usage}%")
            include_df_output = True

    # Check memory usage
    memory_total, memory_available, memory_used, memory_percent = get_memory_usage()
    if memory_percent > threshold_memory:
        alert_message.append(f"Memory usage is high: {memory_percent}%")
        include_memory_usage = True

    # Check CPU usage
    cpu_percentages = get_cpu_usage()
    if max(cpu_percentages) > threshold_cpu:
        alert_message.append(f"CPU usage is high: {max(cpu_percentages)}%")
        include_cpu_usage = True

    # Format data for alerts
    memory_html_row = ""
    if include_memory_usage:
        memory_html_row = format_memory_usage(memory_total, memory_available, memory_used, memory_percent)

    cpu_html_rows = ""
    if include_cpu_usage:
        cpu_html_rows = format_cpu_usage(cpu_percentages)

    df_html_rows = ""
    if include_df_output:
        df_output = get_df_output()
        df_html_rows = format_df_output(df_output)

    # Check if it's time to send a health report
    is_time, slot = is_report_time()
    if is_time:
        send_health_report(slot)

    # Send alert email if thresholds are exceeded
    if alert_message:
        try:
            with open(html_template_path, 'r') as file:
                html_template = file.read()
        except FileNotFoundError:
            print(f"HTML template file not found at {html_template_path}")
            return
        except PermissionError:
            print(f"Permission denied accessing HTML template file at {html_template_path}")
            return

        email_body = html_template.replace("<!-- Data rows for CPU usage will be inserted here -->", cpu_html_rows)
        email_body = email_body.replace("<!-- Data rows for memory usage will be inserted here -->", memory_html_row)
        email_body = email_body.replace("<!-- Data rows for disk usage will be inserted here -->", df_html_rows)
        email_body = "<h2>System Alerts</h2>" + "<br>".join(alert_message) + "<br><br>" + email_body
        send_email(email_alert_subject, email_body)
    else:
        print("No threshold alerts triggered.")

if __name__ == "__main__":
    main()
