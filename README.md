# Tor Multiplexer For Windows
  A windows tool to run multiple tor engines and load balance them with HAProxy.
  
<img width="398" height="531" alt="image" src="https://github.com/user-attachments/assets/4a4a9fea-381f-4326-a4c6-78aaeb21dfda" /> <img width="402" height="532" alt="image" src="https://github.com/user-attachments/assets/e9e6b45b-4857-4931-a323-ff5ddcb9db4f" />




  How it works:

  - The backbone of this software are 8 tor engines, connected together using a tool called HAProxy for load-balancing.
  - v2rayN is also included in the app for easier management of the proxy.
  - This app was made to bypass internet restrictions in heavily restricted areas and because speed is a major concern I thought of putting together a tool that automates the load balancing process for higher speeds in those regions.
    
  How to use:

1- Launch the program with "Launch Multiplexer"

2- Choose your bridge type 

3- Choose to connect with either "fast" or "stable" configuration

4- after the process is complete you can either choose to launch v2rayN with a premade configuration to connect to the multiplexer
or you can use your own proxy management app.
  

1- ابتدا برنامه را با اجرای فایل
"Launch Multiplexer"
اجرا کنید

2- سپس یکی از دو گزینه 
CONNECT (Stable config)
یا
CONNECT (Fast config)
را انتخاب کنید

3- ترجیحا Bridge Type را تغییر ندهید.

4- بعد از اتمام مراحل اجرا میتوانید از طریق 
v2rayN
به کانفیگ از قبل ایجاد شده متصل بشید

Made with love by @RichTitan

https://t.me/richtitan



Credits:

HAProxy: https://github.com/xjoker/HAProxyForWindows

v2rayN: https://github.com/2dust/v2rayN

Tor: https://www.torproject.org/
