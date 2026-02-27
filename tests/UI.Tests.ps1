# ============================================================
# UI.Tests.ps1 - UI.psm1 のユニットテスト
# Pester 5.x
# ============================================================

BeforeAll {
    Import-Module "$PSScriptRoot\..\scripts\lib\UI.psm1" -Force
}

# ============================================================
# Select-Browser
# ============================================================
Describe 'Select-Browser' {

    Context 'パラメータのデフォルト値' {

        It 'DefaultBrowser のデフォルト値が "edge" であること (空入力で Edge が返る)' {
            Mock -CommandName 'Read-Host' -MockWith { return '' } -ModuleName 'UI'
            Mock -CommandName 'Write-Host' -MockWith { } -ModuleName 'UI'

            # DefaultBrowser を指定しない場合、デフォルト "edge" が使われる
            $result = Select-Browser
            $result.Type | Should -Be 'edge'
            $result.Name | Should -Be 'Microsoft Edge'
        }

        It 'EdgeExe のデフォルト値が正しいこと (パラメータ未指定で Edge 選択)' {
            Mock -CommandName 'Read-Host' -MockWith { return '1' } -ModuleName 'UI'
            Mock -CommandName 'Write-Host' -MockWith { } -ModuleName 'UI'

            $result = Select-Browser
            $result.Exe | Should -Be 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
        }

        It 'ChromeExe のデフォルト値が正しいこと (パラメータ未指定で Chrome 選択)' {
            Mock -CommandName 'Read-Host' -MockWith { return '2' } -ModuleName 'UI'
            Mock -CommandName 'Write-Host' -MockWith { } -ModuleName 'UI'

            $result = Select-Browser
            $result.Exe | Should -Be 'C:\Program Files\Google\Chrome\Application\chrome.exe'
        }
    }

    Context 'Read-Host をモックして "1" (Edge) を選択した場合' {

        It 'Edge の情報を含むハッシュテーブルを返すこと' {
            Mock -CommandName 'Read-Host' -MockWith { return '1' } -ModuleName 'UI'
            Mock -CommandName 'Write-Host' -MockWith { } -ModuleName 'UI'

            $result = Select-Browser -DefaultBrowser 'edge'
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'Microsoft Edge'
            $result.Type | Should -Be 'edge'
            $result.Exe  | Should -Be 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
        }
    }

    Context 'Read-Host をモックして "2" (Chrome) を選択した場合' {

        It 'Chrome の情報を含むハッシュテーブルを返すこと' {
            Mock -CommandName 'Read-Host' -MockWith { return '2' } -ModuleName 'UI'
            Mock -CommandName 'Write-Host' -MockWith { } -ModuleName 'UI'

            $result = Select-Browser -DefaultBrowser 'edge'
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'Google Chrome'
            $result.Type | Should -Be 'chrome'
            $result.Exe  | Should -Be 'C:\Program Files\Google\Chrome\Application\chrome.exe'
        }
    }

    Context 'Read-Host をモックして空文字列を返した場合 (デフォルト選択)' {

        It 'DefaultBrowser が "edge" の場合に Edge を返すこと' {
            Mock -CommandName 'Read-Host' -MockWith { return '' } -ModuleName 'UI'
            Mock -CommandName 'Write-Host' -MockWith { } -ModuleName 'UI'

            $result = Select-Browser -DefaultBrowser 'edge'
            $result.Type | Should -Be 'edge'
        }

        It 'DefaultBrowser が "chrome" の場合に Chrome を返すこと' {
            Mock -CommandName 'Read-Host' -MockWith { return '' } -ModuleName 'UI'
            Mock -CommandName 'Write-Host' -MockWith { } -ModuleName 'UI'

            $result = Select-Browser -DefaultBrowser 'chrome'
            $result.Type | Should -Be 'chrome'
        }
    }

    Context 'カスタム Exe パスを指定した場合' {

        It '指定した EdgeExe パスが返るハッシュテーブルに含まれること' {
            Mock -CommandName 'Read-Host' -MockWith { return '1' } -ModuleName 'UI'
            Mock -CommandName 'Write-Host' -MockWith { } -ModuleName 'UI'

            $customExe = 'D:\Custom\edge.exe'
            $result = Select-Browser -EdgeExe $customExe
            $result.Exe | Should -Be $customExe
        }

        It '指定した ChromeExe パスが返るハッシュテーブルに含まれること' {
            Mock -CommandName 'Read-Host' -MockWith { return '2' } -ModuleName 'UI'
            Mock -CommandName 'Write-Host' -MockWith { } -ModuleName 'UI'

            $customExe = 'D:\Custom\chrome.exe'
            $result = Select-Browser -ChromeExe $customExe
            $result.Exe | Should -Be $customExe
        }
    }
}

# ============================================================
# Select-Project
# ============================================================
Describe 'Select-Project' {

    Context 'ProjectRootPath が存在しない場合' {

        It '例外をスローすること' {
            $missingPath = Join-Path $TestDrive 'nonexistent-root'
            { Select-Project -ProjectRootPath $missingPath } | Should -Throw -ExpectedMessage '*プロジェクトルートパスが見つかりません*'
        }
    }

    Context 'ディレクトリが 0 個の場合' {

        BeforeAll {
            $script:EmptyRoot = Join-Path $TestDrive 'empty-root'
            New-Item -ItemType Directory -Path $script:EmptyRoot -Force | Out-Null
        }

        It '例外をスローすること' {
            Mock -CommandName 'Get-ChildItem' -MockWith { return @() } -ModuleName 'UI'
            Mock -CommandName 'Read-Host' -MockWith { return '1' } -ModuleName 'UI'
            Mock -CommandName 'Write-Host' -MockWith { } -ModuleName 'UI'

            { Select-Project -ProjectRootPath $script:EmptyRoot } | Should -Throw -ExpectedMessage '*プロジェクトディレクトリが見つかりません*'
        }
    }

    Context 'Projects パラメータで直接ディレクトリを渡した場合' {

        BeforeAll {
            # テスト用ディレクトリ作成
            $script:ProjRoot = Join-Path $TestDrive 'projects-direct'
            New-Item -ItemType Directory -Path $script:ProjRoot -Force | Out-Null

            $script:DirA = New-Item -ItemType Directory -Path (Join-Path $script:ProjRoot 'ProjectA') -Force
            $script:DirB = New-Item -ItemType Directory -Path (Join-Path $script:ProjRoot 'ProjectB') -Force
        }

        It '渡したディレクトリの中から選択できること' {
            Mock -CommandName 'Read-Host' -MockWith { return '1' } -ModuleName 'UI'
            Mock -CommandName 'Write-Host' -MockWith { } -ModuleName 'UI'

            $result = Select-Project -ProjectRootPath $script:ProjRoot -Projects @($script:DirA, $script:DirB)
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'ProjectA'
        }

        It '2番を選択すると2番目のディレクトリが返ること' {
            Mock -CommandName 'Read-Host' -MockWith { return '2' } -ModuleName 'UI'
            Mock -CommandName 'Write-Host' -MockWith { } -ModuleName 'UI'

            $result = Select-Project -ProjectRootPath $script:ProjRoot -Projects @($script:DirA, $script:DirB)
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'ProjectB'
        }
    }

    Context 'RecentProjects に含まれるプロジェクトがソート順の先頭に来ること' {

        BeforeAll {
            $script:SortRoot = Join-Path $TestDrive 'projects-sort'
            New-Item -ItemType Directory -Path $script:SortRoot -Force | Out-Null

            # アルファベット順: Alpha, Beta, Gamma
            $script:Alpha = New-Item -ItemType Directory -Path (Join-Path $script:SortRoot 'Alpha') -Force
            $script:Beta  = New-Item -ItemType Directory -Path (Join-Path $script:SortRoot 'Beta') -Force
            $script:Gamma = New-Item -ItemType Directory -Path (Join-Path $script:SortRoot 'Gamma') -Force
        }

        It 'RecentProjects の Gamma が先頭に来て、番号 1 で選択できること' {
            Mock -CommandName 'Read-Host' -MockWith { return '1' } -ModuleName 'UI'
            Mock -CommandName 'Write-Host' -MockWith { } -ModuleName 'UI'

            $result = Select-Project -ProjectRootPath $script:SortRoot `
                -Projects @($script:Alpha, $script:Beta, $script:Gamma) `
                -RecentProjects @('Gamma')

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'Gamma'
        }

        It '複数の RecentProjects が指定順で先頭に並ぶこと' {
            Mock -CommandName 'Read-Host' -MockWith { return '2' } -ModuleName 'UI'
            Mock -CommandName 'Write-Host' -MockWith { } -ModuleName 'UI'

            $result = Select-Project -ProjectRootPath $script:SortRoot `
                -Projects @($script:Alpha, $script:Beta, $script:Gamma) `
                -RecentProjects @('Gamma', 'Alpha')

            # 順序: Gamma(1), Alpha(2), Beta(3)
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'Alpha'
        }

        It 'RecentProjects でない Beta が最後尾に来ること' {
            Mock -CommandName 'Read-Host' -MockWith { return '3' } -ModuleName 'UI'
            Mock -CommandName 'Write-Host' -MockWith { } -ModuleName 'UI'

            $result = Select-Project -ProjectRootPath $script:SortRoot `
                -Projects @($script:Alpha, $script:Beta, $script:Gamma) `
                -RecentProjects @('Gamma', 'Alpha')

            # 順序: Gamma(1), Alpha(2), Beta(3)
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'Beta'
        }
    }

    Context 'ドットで始まるディレクトリが除外されること' {

        BeforeAll {
            $script:FilterRoot = Join-Path $TestDrive 'projects-filter'
            New-Item -ItemType Directory -Path $script:FilterRoot -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $script:FilterRoot 'VisibleProject') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $script:FilterRoot '.hidden') -Force | Out-Null
        }

        It 'Get-ChildItem 結果からドットディレクトリがフィルタされ 1件 のみ表示されること' {
            Mock -CommandName 'Read-Host' -MockWith { return '1' } -ModuleName 'UI'
            Mock -CommandName 'Write-Host' -MockWith { } -ModuleName 'UI'

            $result = Select-Project -ProjectRootPath $script:FilterRoot
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'VisibleProject'
        }
    }
}

# ============================================================
# Resolve-ProjectRootPath
# ============================================================
Describe 'Resolve-ProjectRootPath' {

    Context 'ドライブパスが存在する場合' {

        It 'ドライブパスをそのまま返すこと' {
            Mock -CommandName 'Test-Path' -MockWith { return $true } -ModuleName 'UI'
            Mock -CommandName 'Write-Host' -MockWith { } -ModuleName 'UI'

            $result = Resolve-ProjectRootPath -ZRoot 'X:\'
            $result | Should -Be 'X:\'
        }
    }

    Context 'ドライブパス失敗 + UNCパス成功の場合' {

        It 'UNCパスを返すこと' {
            Mock -CommandName 'Test-Path' -MockWith {
                param($Path)
                # 最初の呼び出し (ドライブパス) は失敗、2回目 (UNCパス) は成功
                if ($Path -eq 'X:\') { return $false }
                if ($Path -eq '\\server\share') { return $true }
                return $false
            } -ModuleName 'UI'
            Mock -CommandName 'Write-Host' -MockWith { } -ModuleName 'UI'
            Mock -CommandName 'Write-Warning' -MockWith { } -ModuleName 'UI'

            $result = Resolve-ProjectRootPath -ZRoot 'X:\' -ZUncPath '\\server\share'
            $result | Should -Be '\\server\share'
        }
    }

    Context 'ドライブパスとUNCパスの両方が失敗する場合' {

        It '例外をスローすること' {
            Mock -CommandName 'Test-Path' -MockWith { return $false } -ModuleName 'UI'
            Mock -CommandName 'Write-Host' -MockWith { } -ModuleName 'UI'
            Mock -CommandName 'Write-Warning' -MockWith { } -ModuleName 'UI'

            { Resolve-ProjectRootPath -ZRoot 'X:\' -ZUncPath '\\server\share' } |
                Should -Throw -ExpectedMessage '*ドライブパスとUNCパスの両方にアクセスできません*'
        }
    }

    Context 'UNCパス未指定でドライブパス失敗の場合' {

        It '例外をスローすること' {
            Mock -CommandName 'Test-Path' -MockWith { return $false } -ModuleName 'UI'
            Mock -CommandName 'Write-Host' -MockWith { } -ModuleName 'UI'
            Mock -CommandName 'Write-Warning' -MockWith { } -ModuleName 'UI'

            { Resolve-ProjectRootPath -ZRoot 'X:\' } |
                Should -Throw -ExpectedMessage '*プロジェクトルートパスにアクセスできません*'
        }
    }

    Context 'UNCパスが空文字列の場合' {

        It 'ドライブパスの失敗でUNCフォールバックせず例外をスローすること' {
            Mock -CommandName 'Test-Path' -MockWith { return $false } -ModuleName 'UI'
            Mock -CommandName 'Write-Host' -MockWith { } -ModuleName 'UI'
            Mock -CommandName 'Write-Warning' -MockWith { } -ModuleName 'UI'

            { Resolve-ProjectRootPath -ZRoot 'X:\' -ZUncPath '' } |
                Should -Throw -ExpectedMessage '*プロジェクトルートパスにアクセスできません*'
        }
    }
}
