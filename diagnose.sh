#!/bin/bash
# 快速诊断脚本 - 检查部署状态

BASE_URL="${BASE_URL:-https://shellstack.910918920801.xyz}"

echo "=========================================="
echo "ShellStack 部署诊断工具"
echo "=========================================="
echo ""
echo "检查 URL: ${BASE_URL}"
echo ""

# 检查主脚本
echo "1. 检查主脚本 (shellstack.sh)..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/shellstack.sh" 2>/dev/null)
if [[ "$HTTP_CODE" == "200" ]]; then
    echo "   ✓ 主脚本可访问 (HTTP $HTTP_CODE)"
    # 检查脚本内容
    FIRST_LINE=$(curl -s "${BASE_URL}/shellstack.sh" | head -1)
    if [[ "$FIRST_LINE" == "#!/bin/bash" ]]; then
        echo "   ✓ 脚本格式正确"
    else
        echo "   ✗ 警告: 脚本格式可能不正确"
        echo "     第一行: $FIRST_LINE"
    fi
else
    echo "   ✗ 主脚本不可访问 (HTTP $HTTP_CODE)"
    echo "   可能原因:"
    echo "     - 文件尚未部署"
    echo "     - Web 服务器配置错误"
    echo "     - 文件路径不正确"
fi

echo ""

# 检查模块列表
echo "2. 检查模块列表文件 (modules.txt)..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/modules.txt" 2>/dev/null)
if [[ "$HTTP_CODE" == "200" ]]; then
    echo "   ✓ 模块列表可访问 (HTTP $HTTP_CODE)"
    MODULES=$(curl -s "${BASE_URL}/modules.txt" | grep -v "^#" | grep -v "^$" | head -5)
    if [[ -n "$MODULES" ]]; then
        echo "   发现的模块:"
        echo "$MODULES" | sed 's/^/     - /'
    fi
else
    echo "   ✗ 模块列表不可访问 (HTTP $HTTP_CODE)"
fi

echo ""

# 检查 modsecurity 模块
echo "3. 检查 modsecurity 模块..."
for entry in "main.sh" "run.sh" "install.sh"; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/modsecurity/${entry}" 2>/dev/null)
    if [[ "$HTTP_CODE" == "200" ]]; then
        echo "   ✓ modsecurity/${entry} 可访问 (HTTP $HTTP_CODE)"
        break
    fi
done

if [[ "$HTTP_CODE" != "200" ]]; then
    echo "   ✗ modsecurity 模块入口文件不可访问"
fi

echo ""

# 测试脚本执行
echo "4. 测试脚本执行..."
if curl -s "${BASE_URL}/shellstack.sh" | bash -s --list > /tmp/shellstack_test.log 2>&1; then
    echo "   ✓ 脚本可以正常执行"
    echo "   输出预览:"
    head -10 /tmp/shellstack_test.log | sed 's/^/     /'
else
    echo "   ✗ 脚本执行失败"
    echo "   错误信息:"
    tail -5 /tmp/shellstack_test.log | sed 's/^/     /'
fi
rm -f /tmp/shellstack_test.log

echo ""
echo "=========================================="
echo "诊断完成"
echo "=========================================="
echo ""
echo "如果发现问题，请参考 TROUBLESHOOTING.md"
echo "或使用 deploy-manual.sh 进行手动部署"

