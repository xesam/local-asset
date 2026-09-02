package io.github.xesam.android.localasset.sample.feature

import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue

class SampleFlowContractTest {
    @Test
    fun sample_assets_exist_for_all_fixture_backed_flows() {
        assertTrue(File("../../shared/demo/pages/static-mapping.html").exists())
        assertTrue(File("../../shared/demo/pages/directory-routing.html").exists())
        assertTrue(File("../../shared/demo/pages/jsbridge-image-picker.html").exists())
        assertTrue(File("../../shared/demo/pages/handle-lifecycle.html").exists())
        assertTrue(File("../../shared/demo/pages/security-models.html").exists())
        assertTrue(File("../../shared/demo/pages/error-categories.html").exists())
        assertTrue(File("../../shared/demo/pages/resolver-chain.html").exists())
        assertTrue(File("../../shared/demo/pages/graceful-degradation.html").exists())
    }

    @Test
    fun removed_flows_no_longer_have_assets() {
        assertTrue(!File("../../shared/demo/pages/rule-override.html").exists())
        assertTrue(!File("../../shared/demo/pages/fallback.html").exists())
    }

    @Test
    fun android_sample_fixture_contains_expected_flow_names() {
        val fixture = File("../../docs/compatibility-fixtures/android-sample-flows.json").readText()
        assertTrue(fixture.contains("sample-static-mapping-flow"))
        assertTrue(fixture.contains("sample-directory-routing-flow"))
        assertTrue(fixture.contains("sample-jsbridge-image-picker-flow"))
        assertTrue(fixture.contains("sample-handle-lifecycle-flow"))
        assertTrue(fixture.contains("sample-security-models-flow"))
        assertTrue(fixture.contains("sample-error-categories-flow"))
        assertTrue(fixture.contains("sample-resolver-chain-flow"))
        assertTrue(fixture.contains("sample-graceful-degradation-flow"))
        assertTrue(!fixture.contains("sample-rule-override-flow"))
        assertTrue(!fixture.contains("sample-fallback-flow"))
    }

    @Test
    fun bridge_page_submits_preview_uri_not_token() {
        val shell = File("../../shared/demo/pages/jsbridge-image-picker.html").readText()
        assertTrue(shell.contains("submitImage(currentSelection.previewUri)"))
        assertTrue(!shell.contains("submitImage(currentSelection.token)"))
    }

    @Test
    fun bridge_fixture_uses_parseable_preview_uri_shape() {
        val fixture = File("../../docs/compatibility-fixtures/android-sample-flows.json").readText()
        assertTrue(fixture.contains("local-asset://bridge.demo.local/preview/demo-image-id/demo-image.jpg"))
    }

    @Test
    fun ui_css_exists_and_declares_page_level_scroll_guard() {
        val css = File("../../shared/demo/pages/_ui.css")
        assertTrue(css.exists())
        val text = css.readText()
        // 断言整块而非单条 —— 单看 "max-width: 100%" 会被文件末尾的 img 规则
        // 满足，页面级守卫（本文件存在的全部理由）被删掉测试依然绿。
        // 用块级正则而非三条 contains 相与：后者只要求这些声明存在于文件某处，
        // 把它们挪进一个没人用的选择器同样能骗过，且会被缩进变化误伤。
        assertTrue(
            Regex("""html,\s*body\s*\{[^}]*max-width\s*:\s*100%""").containsMatchIn(text),
        )
        assertTrue(
            Regex("""html,\s*body\s*\{[^}]*overflow-x\s*:\s*hidden""").containsMatchIn(text),
        )
        // 长 URI / token 串就地折行
        assertTrue(text.contains("overflow-wrap: anywhere"))
        // 只加 max-width，不得覆盖演示负载 CSS 的 width
        assertTrue(text.contains("img { max-width: 100%; }"))
        // 用 (?<![-\w]) 而非 \b —— \b 在 max-width 的连字符处成立，
        // 会让本断言在正确的文件上误报失败。
        assertTrue(!Regex("""img\s*\{[^}]*(?<![-\w])width\s*:""").containsMatchIn(text))
    }

    @Test
    fun ui_css_is_not_loaded_through_the_local_asset_engine() {
        // _ui.css 是页面底座，走普通相对路径；用引擎 scheme 引用会让它
        // 在引擎配置出问题时一并失效，守卫规则随之消失。
        //
        // 只禁「引用」，不禁注释里提及 —— 注释正是解释 _ui.css 与演示负载
        // 区别的地方，而那个区别的名字就是 local-asset:// 本身。故先剥注释。
        val text = File("../../shared/demo/pages/_ui.css").readText()
        val code = text.replace(Regex("""/\*.*?\*/""", RegexOption.DOT_MATCHES_ALL), "")
        assertTrue(!code.contains("@import"))
        // 单斜杠形式（local-asset:cdn.demo.local/x.css）同样会路由进引擎
        assertTrue(!code.contains("local-asset:"))
    }

    @Test
    fun ui_css_does_not_reintroduce_sticky_positioning() {
        // 082a58c：sticky/fixed 在 ArkWeb 真机上不生效，该特性已被弃用。
        // 用正则而非子串 —— 那次回退源于真机故障，守卫不该被删掉一个空格绕过。
        val text = File("../../shared/demo/pages/_ui.css").readText()
        assertTrue(!Regex("""position\s*:\s*(sticky|fixed)""").containsMatchIn(text))
    }

    @Test
    fun all_content_pages_link_the_shared_scroll_guard() {
        val pages = listOf(
            "directory-routing", "static-mapping", "resolver-chain",
            "graceful-degradation", "handle-lifecycle", "jsbridge-image-picker",
            "security-models", "error-categories",
        )
        for (page in pages) {
            val html = File("../../shared/demo/pages/$page.html").readText()
            assertTrue(
                html.contains("""<link rel="stylesheet" href="_ui.css">"""),
                "$page.html 未引入 _ui.css",
            )
        }
    }

    @Test
    fun scroll_guard_link_precedes_any_engine_loaded_stylesheet() {
        // 守卫是底座，演示负载可在其上覆盖自己的布局；顺序反了守卫会盖掉演示效果。
        val pages = listOf("directory-routing", "static-mapping", "resolver-chain")
        for (page in pages) {
            val html = File("../../shared/demo/pages/$page.html").readText()
            val guard = html.indexOf("href=\"_ui.css\"")
            val payload = html.indexOf("href=\"local-asset://")
            assertTrue(guard >= 0, "$page.html 未引入 _ui.css")
            assertTrue(payload >= 0, "$page.html 未引用演示负载 CSS")
            assertTrue(guard < payload, "$page.html 的 _ui.css 必须排在演示负载之前")
        }
    }

    @Test
    fun index_page_inlines_the_guard_instead_of_linking_it() {
        // index.html 必须零外部依赖：引擎配置出错时它仍须是可用的入口列表。
        //
        // 检查真实引用而非字面量 —— 断言「不含 local-asset://」既拦不住
        // <script src="https://..."> 这类真外部依赖，又会被注释里的散文误伤。
        val html = File("../../shared/demo/pages/index.html").readText()
        val markup = html.replace(Regex("""<!--.*?-->""", RegexOption.DOT_MATCHES_ALL), "")
        val opts = setOf(RegexOption.IGNORE_CASE)
        // 只查会拉取子资源的标签。<a href> 是页面间导航 —— 那正是本页存在的理由，
        // 不是外部依赖；按标签名而非按属性名筛，才不会把导航链接一并禁掉。
        assertTrue(
            !Regex(
                """<(link|script|img|iframe|source|embed|object|video|audio)\b[^>]*\b(href|src|data)\s*=""",
                opts,
            ).containsMatchIn(markup),
        )
        // 无 <link> 的页面里，@import 是引入外部依赖最顺手的方式
        assertTrue(!markup.contains("@import"))
        assertTrue(!markup.contains("url("))
        assertTrue(html.contains("overflow-x: hidden"))
        assertTrue(html.contains("overflow-wrap: anywhere"))
    }

    @Test
    fun index_inline_guard_does_not_drift_from_the_shared_stylesheet() {
        // 计划刻意让 index.html 重复一份守卫规则（零依赖），代价是两处会各自漂移。
        // 两边注释都写了「请同步另一处」，但注释是唯一的执行力 —— 而注释正是最会烂的东西。
        //
        // 逐条锚定到选择器块，而非 contains 字面量 —— 后者只要求声明存在于文件某处，
        // 挪进死选择器、或整块注释掉，都能骗过。这与本文件 ui_css_* 测试同一条教训。
        val strip = { s: String ->
            s.replace(Regex("""<!--.*?-->""", RegexOption.DOT_MATCHES_ALL), "")
                .replace(Regex("""/\*.*?\*/""", RegexOption.DOT_MATCHES_ALL), "")
        }
        val css = strip(File("../../shared/demo/pages/_ui.css").readText())
        val index = strip(File("../../shared/demo/pages/index.html").readText())
        val guards = mapOf(
            "html,body max-width" to Regex("""html,\s*body\s*\{[^}]*max-width\s*:\s*100%"""),
            "html,body overflow-x" to Regex("""html,\s*body\s*\{[^}]*overflow-x\s*:\s*hidden"""),
            "body overflow-wrap" to Regex("""(?m)^\s*body\s*\{[^}]*overflow-wrap\s*:\s*anywhere"""),
            "box-sizing" to Regex("""\*::before[^{]*\{[^}]*box-sizing\s*:\s*border-box"""),
            "img max-width" to Regex("""img\s*\{[^}]*max-width\s*:\s*100%"""),
        )
        for ((name, pattern) in guards) {
            assertTrue(pattern.containsMatchIn(css), "_ui.css 缺少 $name")
            assertTrue(pattern.containsMatchIn(index), "index.html 内联副本缺少 $name")
        }
        // 两边都不得给 img 设 width（会覆盖演示负载 CSS 的固定尺寸）
        val imgWidth = Regex("""img\s*\{[^}]*(?<![-\w])width\s*:""")
        assertTrue(!imgWidth.containsMatchIn(css))
        assertTrue(!imgWidth.containsMatchIn(index))
        // 值漂移：后写的同名声明会覆盖守卫（如 html,body{overflow-x:auto}）。
        // 各属性在两份副本里的出现次数都必须固定 —— max-width 是 2 次
        // （html,body 与 img 各一），另两个各 1 次。
        val occurrences = mapOf(
            "overflow-x" to 1,
            "max-width" to 2,
            "overflow-wrap" to 1,
        )
        for ((property, expected) in occurrences) {
            val pattern = Regex(Regex.escape(property) + """\s*:""")
            assertTrue(
                pattern.findAll(css).count() == expected,
                "_ui.css 的 $property 出现次数应为 $expected",
            )
            assertTrue(
                pattern.findAll(index).count() == expected,
                "index.html 内联副本的 $property 出现次数应为 $expected",
            )
        }
    }

    @Test
    fun bridge_activity_uses_formal_handle_registry_api() {
        val source = demoActivitySource()
        assertTrue(source.contains("localAsset.registerHandle("))
        assertTrue(source.contains("localAsset.resolveHandle(previewUri)"))
        assertTrue(source.contains("localAsset.removeHandle("))
    }

    @Test
    fun handle_lifecycle_activity_uses_handle_lifecycle_api() {
        val source = demoActivitySource()
        assertTrue(source.contains("localAsset.registerHandle("))
        assertTrue(source.contains("ttlMillis"))
        assertTrue(source.contains("localAsset.resolveHandle("))
        assertTrue(source.contains("localAsset.removeHandle("))
    }

    @Test
    fun security_models_activity_contrasts_handle_and_registry_paths() {
        val activity = demoActivitySource()
        val engine = demoEngineSource()
        // Handle path (capability)
        assertTrue(activity.contains("registerHandle("))
        // Registry path with ENGINE scope (namespace/scope model)
        assertTrue(engine.contains("ResourceScope.ENGINE"))
        assertTrue(engine.contains("engine-matched"))
        assertTrue(engine.contains("engine-mismatch"))
        // Native probe via engine.resolve surfaces the SECURITY_ERROR category
        assertTrue(activity.contains("localAsset.engine.resolve("))
        assertTrue(activity.contains("EngineResult.Failure"))
    }

    @Test
    fun error_categories_activity_drives_four_categories_via_engine_resolve() {
        val source = demoActivitySource()
        assertTrue(source.contains("localAsset.engine.resolve("))
        assertTrue(source.contains("EngineResult.Failure"))
        assertTrue(source.contains("parse"))
        assertTrue(source.contains("resolution"))
        assertTrue(source.contains("load"))
        assertTrue(source.contains("security"))
    }

    @Test
    fun error_categories_table_scrolls_inside_its_own_container() {
        val html = File("../../shared/demo/pages/error-categories.html").readText()
        // 断言 div 真的包住了 table —— 只查 `<div class="scroll-x">` 字符串存在，
        // 留一个空壳 div 而把 table 挪到外面同样能通过，容器的作用当场归零。
        assertTrue(Regex("""<div class="scroll-x">\s*<table>""").containsMatchIn(html))
        assertTrue(Regex("""</table>\s*</div>""").containsMatchIn(html))
        assertTrue(html.contains(".scroll-x { overflow-x: auto;"))
        // min-width 是必需的：没有它表格会被压到 100% 宽后逐字折行，
        // 容器永远不产生滚动条，包了等于没包。
        assertTrue(html.contains(".scroll-x table { min-width: 560px; }"))
    }

    @Test
    fun error_categories_keeps_comparison_columns_on_one_line() {
        // category 与 stage 两列并排才有对照价值 —— 这正是本页要演示的东西，
        // 也是它成为唯一横滚例外的理由。二者都必须 nowrap。
        //
        // stage 的实际取值来自 EngineObserver.STAGE_*，最长的是 adapter_parse
        // （13 字符）。而 _ui.css 的 overflow-wrap: anywhere 会继承进表格，
        // 允许逐字断行 —— 少了 nowrap，adapter_parse 会被拆成三行。
        val html = File("../../shared/demo/pages/error-categories.html").readText()
        assertTrue(
            Regex("""td\.cat\s*\{[^}]*white-space\s*:\s*nowrap""").containsMatchIn(html),
        )
        assertTrue(
            Regex("""\.stage\s*\{[^}]*white-space\s*:\s*nowrap""").containsMatchIn(html),
        )
    }

    @Test
    fun resolver_chain_activity_short_circuits_with_custom_resolver_before_base() {
        val source = demoEngineSource()
        // Custom resolver added first short-circuits on Hit for the overridden path
        assertTrue(source.contains("ResourceResolver { request, _ ->"))
        assertTrue(source.contains("ResolverResult.Hit"))
        assertTrue(source.contains("/base/banner.svg"))
        // Base directory resolver added second handles the rest
        assertTrue(source.contains("AssetDirectoryResolver"))
        assertTrue(source.contains("chain.demo.local"))
    }

    @Test
    fun graceful_degradation_activity_revokes_handle_and_serves_static() {
        val engine = demoEngineSource()
        assertTrue(engine.contains("InMemoryHandleRegistry"))
        assertTrue(engine.contains("AssetDirectoryResolver"))
        assertTrue(engine.contains("resilient.demo.local"))
        // Register then immediately revoke — the page requests the revoked URI and degrades
        val activity = demoActivitySource()
        assertTrue(activity.contains("localAsset.registerHandle("))
        assertTrue(activity.contains("localAsset.removeHandle("))
    }

    /**
     * 演示导航改由共享 HTML 承担后，原先 8 个 Activity 合并成了这一个容器，
     * 8 套引擎配置合并进了 DemoEngine。下面两个读取点即那次合并后的落点 ——
     * 上面这些断言检查的仍是同一批能力，只是不再按场景分文件。
     */
    private fun demoActivitySource(): String =
        File("src/main/kotlin/io/github/xesam/android/localasset/sample/DemoActivity.kt").readText()

    private fun demoEngineSource(): String =
        File("src/main/kotlin/io/github/xesam/android/localasset/sample/DemoEngine.kt").readText()
}
