@echo off
if exist %drivepath%\Drivers.log del %drivepath%\Drivers.log
if exist %drivepath%\Drivers dir /s /b %Drivepath%\Drivers\bootcritical\*.inf >>%Drivepath%\Drivers.log
if exist %drivepath%\Drivers for /f %%a in (%Drivepath%\Drivers.log) do (drvload %%a)
if exist %drivepath%\Drivers.log del %drivepath%\Drivers.log