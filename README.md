# Tor Multiplexer For Windows
  A windows tool to run multiple tor engines and load balance them with HAProxy.
  Tor but faster!
  
<img width="601" height="382" alt="Screenshot 2026-05-11 214452" src="https://github.com/user-attachments/assets/035b80eb-b49e-485b-ad17-426c5703856b" /> <img width="600" height="383" alt="Screenshot 2026-05-11 214323" src="https://github.com/user-attachments/assets/f5a45146-62e0-4db5-b35b-99fd9dd8fca3" />






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

Made with love by @RichTitan

https://t.me/richtitan



Credits:

HAProxy: https://github.com/xjoker/HAProxyForWindows

v2rayN: https://github.com/2dust/v2rayN

xray: https://github.com/xtls/xray-core

Tor: https://www.torproject.org/
