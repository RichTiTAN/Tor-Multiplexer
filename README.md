# Tor Multiplexer For Windows
  A windows tool to run multiple tor connections and load balance them with HAProxy with a simple and feature-full UI.
  Tor but faster!
  
<img width="591" height="287" alt="Screenshot 2026-05-14 212929" src="https://github.com/user-attachments/assets/19250f34-45b6-40bd-88f8-18c433451c84" /> <img width="591" height="441" alt="Screenshot 2026-05-14 222110" src="https://github.com/user-attachments/assets/2ba6bed1-8d60-475f-ad02-8ff28b12fde7" /> <img width="897" height="476" alt="Screenshot 2026-05-16 161759" src="https://github.com/user-attachments/assets/9574b9ed-bd6d-4db8-a8d9-77cb0fca1a3c" />












  How it works:

  - The backbone of this software are 8 tor engines, connected together using a tool called HAProxy for load-balancing.
  - xray core is also included in the app for easier management of the proxy.
  - This app was made to bypass internet restrictions in heavily restricted areas and because speed is a major concern I thought of putting together a tool that automates the load balancing process for higher speeds in those regions.
    
  How to use:

!!It is recommended to keep the default settings unless you want to change the bridge type!!

1- Launch the program with "Launch Multiplexer"

2- Choose your bridge type and configuration and the amount of tor engines you want to run

3- Press connect

!!Proxy mode enables a system-wide proxy and Clear proxy gives you a local proxy port so you can use your own proxy management app!!
  

1- ابتدا برنامه را با اجرای فایل
"Launch Multiplexer"
اجرا کنید

2- سپس گزینه "Connect" را انتخاب کنید

3- گزینه Proxy mode پروکسی سیستم شما را فعال میکند و میتوانید در هر اپلیکیشنی از آن استفاده کنید. گزینه Clear proxy به شما پورت داخلی برای استفاده در اپلیکیشن پروکسی شخصی شما میدهد. 

Made with love by [@itsTiTANVPN](https://t.me/itsTitanVPN) and my buddy Gemini





Credits:

HAProxy: https://github.com/xjoker/HAProxyForWindows

v2rayN: https://github.com/2dust/v2rayN

xray: https://github.com/xtls/xray-core

Tor: https://www.torproject.org/

Sing_Box: https://github.com/SagerNet/sing-box
