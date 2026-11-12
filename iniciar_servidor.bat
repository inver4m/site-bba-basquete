@echo off
title BBA League - Servidor Local
cls
echo Iniciando servidor BBA League...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
pause

