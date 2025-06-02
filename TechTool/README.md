# 🧰 TechTool – The Ultimate PowerShell Toolkit for Technicians

**Created by [Aymen EL JAZIRI](https://www.linkedin.com/in/aymeneljaziri/)**  
📅 First release: February 2023  
💻 Platform: Windows Server & Workstations

---

## 🚀 Introduction

**TechTool** is a versatile PowerShell script designed to simplify and accelerate daily tasks for system administrators and IT technicians. It provides an interactive command-line menu to quickly access essential diagnostics, audit logs, cleanup tools, and even automate software installation — all from one place.

This script was built out of real-world needs for managing Windows servers and environments more efficiently, especially in RDP or on-prem server contexts.

---

## ✨ Features

### 🔧 System Tools

| Option | Description |
|--------|-------------|
| 1️⃣ | View recent server restarts or shutdowns (last 30 days) using Event Logs |
| 2️⃣ | List installed Windows updates (KBs) sorted by date |
| 3️⃣ | Check for pending Windows Updates not yet installed |
| 4️⃣ | Display Windows Defender antivirus and protection status |
| 5️⃣ | Audit logon/logoff history of users on the server |
| 6️⃣ | Scan folders for large files recently modified (last 15 days) |
| 7️⃣ | Show the last 50 critical system errors from Event Logs |
| 8️⃣ | List all currently stopped Windows services |
| 9️⃣ | Clean up system temp files and Windows Update cache |
| 🔟 | Get IP geolocation details using the public IP (via `ipinfo.io` API) |

---

### 💻 Software Installation Tools

Install useful IT tools silently with a single click:

| Option | Tool |
|--------|------|
| 2️⃣0️⃣ | Google Chrome (silent install via direct link) |
| 2️⃣1️⃣ | Brave Browser (silent install via official source) |
| 2️⃣2️⃣ | Advanced IP Scanner |
| 2️⃣3️⃣ | TreeSize (downloaded via Google Drive link with token handling) |

---

## 📦 How to Use

1. **Download or clone this repository**
   ```bash
   git clone https://github.com/yourusername/TechTool.git
   ```
