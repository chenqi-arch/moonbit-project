# MoonVCR 0.3.2 独立审核整改与验收

## 范围与基线

依据用户指定的“审核 Moonbit 已实现功能”对话及其 2026-10-31 审核报告，逐项处理 F1–F7。审核源码基线为 `15c8a49`，正式包为 `0.3.1`。本轮保留独立审核目录原文件和旧标签，不回写基线、不放宽原始断言，不把静态问题说成已经运行复现。

导入 `audit_regression_test.mbt` 的原始 10 项测试：修前实际 **2 通过、8 失败**；修复后的本地执行为 **10/10 通过**。8 个失败不等于 8 个独立漏洞：F1 对应必填/可选/契约三个失败，F2 对应 query/header 两个失败，F5/F6/F7 各一个。F3/F4 原报告为静态发现，本轮增加 native 实际验收，不计入这 8 项。

## 修改方案与落地标准

| 发现 | 修复实现 | 可复验通过标准 |
| --- | --- | --- |
| F1 空白 Pointer 键导致留密与契约误检 | Pointer 保留原文；dot shorthand 单独解析；契约复用精确寻址 | 空格/Tab/换行 × required/optional × 请求/响应共12组合，无秘密留存；相邻键不被误改，错误类型契约拒绝；Unicode、空键、转义键有正反例 |
| F2 重复 query/header 顺序丢失 | 按名称分组排序，组内按原始下标保序；编码别名同组；query值不 trim | 相反重复值顺序必须不同键、ReplayMiss且不消费；不同名称可重排；编码别名、同值、空白控制通过 |
| F3 native 头/Cookie 丢失 | 发网前拒绝重复请求头；恢复独立 response.cookies 为逐条 Set-Cookie | 类型化错误不含秘密且不录制；真实 HTTP 双 Cookie 的值与公开属性对业务可见，保存副本两条均脱敏、离线可回放 |
| F4 stat 后全读无硬预算 | 一次打开，同句柄4096字节分块读取，最多消费预算加一字节 | 精确上限成功、上限加一在解码前拒绝；无限流/短读/块边界、Int64.MAX、读错误；确定性路径替换与打开后增长都不绕过预算 |
| F5 诊断和真实回放判等不同 | 判等直接复用实际请求键输入，安全显示另做脱敏摘要 | 同Session ReplayMiss时有差异；原始导入 token/header 不出现在报告；独立3600组合诊断空差异当且仅当回放成功 |
| F6 非法数组索引被接受 | 严格十进制且无前导零；契约区分非法与合法缺失 | required/optional/数组契约拒绝01、+1、-、溢出等；对象字段01与合法0控制通过 |
| F7 重叠规则依赖顺序 | 全部规则先验证原始JSON，再深到浅替换 | 父子规则各种排列及重复规则输出一致；缺失必填/非法可选不能被父级替换隐藏 |

## 测试与独立复核

- 原始审核测试：`moon test --target wasm audit_regression_test.mbt --serial`。
- 路径与契约扩展：`audit_paths_test.mbt`；匹配/诊断/可选索引：`audit_matching_test.mbt`；独立组合复核固化为 `audit_consistency_test.mbt`。
- native HTTP：`native/http_headers_test.mbt` 与 `cmd/moonvcr-native-http-acceptance`；loopback 服务提供双 Set-Cookie 和属性控制。
- native 文件预算：`native/archive_limits_wbtest.mbt`，含真实同句柄替换/增长控制，不以睡眠或概率竞争代替验证。
- 公开API验收：`moon run cmd/moonvcr-security-acceptance` 同时运行既有12条非Text拒绝/1024编码组合及新12条空白Pointer、重复顺序、诊断、索引、重叠规则。`scripts/verify-public-consumer.ps1` 在候选ZIP与正式公网包上运行同一断言；两者分别记录来源。
- 三个子代理分别负责路径语义、HTTP与匹配诊断、文件预算，并二次独立复核。组合数不冒充独立测试数，native总数包含核心，不能相加。

## 当前执行状态

修复提交 `5bea80bc203375b728999b6f047ff834e71c32a5` 的 [CI41185113305](https://github.com/chenqi-arch/moonbit-project/actions/runs/41185113305) check/native全绿；实际moonc0.10.14，核心129/129、native154/154（包含核心）。真实HTTP验证输出包含 `duplicate-header-rejection two-set-cookie business-original redacted-cassette offline-cookie-replay`，真实录制2条秘密留存0、关服后新进程回放2条网络调用0。F3/F4已获得Ubuntu实际运行证据，不再仅依赖类型检查。

本地候选归档消费者及CI候选消费者均输出新12条Pointer留存0及既有12拒绝/1024编码通过。最终发布提交为 `a5b3b4634d77b360226e8f6350fe228cbbc86206`，tag `v0.3.2`，对应 [CI41185323935](https://github.com/chenqi-arch/moonbit-project/actions/runs/41185323935) check/native全绿（129/154，含相同native实测）。发布归档87文件与干净提交工作树逐文件一致，含LICENSE、无申报书/真实联系方式/访问令牌。

Mooncakes预演服务端返回202 Accepted（旧CLI虽报exit -1，但明确写明dry-run成功且未产生变更，未伪称CLI零退出）；正式发布返回200 OK、退出0。正式包： https://mooncakes.io/docs/chenqi-arch/moonbit-project@0.3.2 。新消费者日志明确下载0.3.2，README、全部新旧安全断言和私有字段编译负例通过，`origin=public-registry`。

发布审核子代理另用空MOON_HOME `_build/public-audit-032-c659a31a` 与消费者 `_build/c-946de674/consumer`，日志明确下载0.3.2与async0.22.1，相同断言退出0；下载包、ZIP、冻结工作树的87文件三方SHA256一致。不使用主代理缓存冒充全新下载。后续文档与CI收尾提交不冒充发布包源码，不移动旧tag。

另在隔离归档副本中覆盖未经改写的审核原始测试文件，校验复制哈希一致后执行，10/10通过。对正式下载包运行审核原始public-proof脚本也退出0：12次录制错误0、留密0，错误重复query回放false，错误类型空白键契约通过false。脚本输出中固定的 `published_0_3_1` 标签为原审核文字，实际依赖manifest已核对为0.3.2。CI现默认从公网下载0.3.2执行完整断言，旧0.3.1仅保留历史影响说明。

## 行为与边界

JSON Pointer为空字符串的整文档根路径未支持；`/`支持空对象键。重复请求头由native明确拒绝，不能声称底层支持任意重复头。Cookie按依赖公开数据规范化重建，不承诺HTTP原始字节。`TooLarge(n)`为已读取的超限字节数下界，Bytes的Int可表示长度也会限制极大输入。

不同名称的query全局顺序不参与当前匹配；编码拼写等价可保守未命中。HTTP完整响应API仍无响应字节硬上限，不把文件预算冒充网络内存预算。旧cassette不会自动清洗，需审阅重录。TLS握手、取消写入及故障注入没有新实测时不声明完成。新修复降低已发现问题的风险，不保证所有输入无漏洞或代替主办方决定。
