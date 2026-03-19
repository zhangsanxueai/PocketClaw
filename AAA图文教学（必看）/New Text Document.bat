@echo off
chcp 65001 >nul
cd /d "C:\Users\xiaomi\Desktop\PocketClaw\AAA图文教学（必看）"

rem 从大到小重命名，避免覆盖冲突
ren "步骤10.png" "步骤11.png"
ren "步骤9.jpg" "步骤10.jpg"
ren "步骤8.png" "步骤9.png"
ren "步骤7.png" "步骤8.png"
ren "步骤6.png" "步骤7.png"
ren "步骤5.png" "步骤6.png"
ren "步骤4.jpg" "步骤5.jpg"
ren "步骤3.png" "步骤4.png"
ren "步骤2.png" "步骤3.png"
ren "步骤1.png" "步骤2.png"

echo 重命名完成！
pause