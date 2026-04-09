import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Widgets

// Panel Component
Item {
    id: root

    readonly property bool allowAttach: true
    readonly property string bin: platform === 'gitlab' ? 'glab' : 'gh'
    property var cfg: pluginApi?.pluginSettings || ({})
    property real contentPreferredHeight: 260 * Style.uiScaleRatio
    property real contentPreferredWidth: 440 * Style.uiScaleRatio
    property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

    // SmartPanel
    readonly property var geometryPlaceholder: panelContainer
    property bool isAuthenticated: true
    property bool isBinInstalled: true
    property string issues: cfg.issues ?? defaults.issues
    property string prs: cfg.prs ?? defaults.prs
    property bool loading: false
    readonly property string platform: cfg.platform ?? defaults.platform

    // Plugin API (injected by PluginPanelSlot)
    property var pluginApi: null
    property string prString: platform === 'gitlab' ? "Merge Requests" : "Pull Requests"
    property var repoList: cfg.repoList ?? []
    property string selectedRepo: cfg.selectedRepo ?? defaults.selectedRepo
    property var user: cfg.user ?? {
        name: "",
        avatar: "",
        bio: ""
    }

    function refreshRepoStats() {
        issueProcess.running = true;
        prProcess.running = true;
    }
    function startCheck() {
        isBinInstalled = true;
        isAuthenticated = true;

        loading = repoList.length === 0;
        binProcess.running = true;
    }

    anchors.fill: parent

    onBinChanged: {
        startCheck();
    }
    onSelectedRepoChanged: {
        refreshRepoStats();
    }

    Timer {
        interval: (cfg.refreshInterval ?? defaults.refreshInterval) * 1000
        repeat: true
        running: true
        triggeredOnStart: true

        onTriggered: {
            startCheck();
        }
    }
    Process {
        id: binProcess

        command: [bin, "--version"]
        running: false

        onExited: exitCode => {
            if (exitCode !== 0) {
                root.isBinInstalled = false;
            } else {
                authProcess.running = true;
            }
        }
    }
    Process {
        id: authProcess

        command: [bin, "auth", "status"]
        running: false

        onExited: exitCode => {
            if (exitCode !== 0) {
                root.isAuthenticated = false;
                root.loading = false;
            } else {
                userProcess.running = true;
            }
        }
    }
    Process {
        id: userProcess

        command: platform === 'gitlab' ? ["glab", "api", "/user", "--output", "ndjson"] : ["gh", "api", "user", "--jq", "[.login, .avatar_url, .bio] | @tsv"]
        running: false

        stdout: SplitParser {
            onRead: data => {
                try {
                    if (platform === 'gitlab') {
                        const user = JSON.parse(data);
                        root.user = {
                            name: user.username || "",
                            avatar: user.avatar_url || "",
                            bio: user.bio || ""
                        };
                    } else {
                        const parts = data.trim().split("\t");
                        root.user = {
                            name: parts[0] || "",
                            avatar: parts[1] || "",
                            bio: parts[2] || ""
                        };
                    }
                } catch (error) {
                    Logger.e(error.message);
                }
            }
        }

        onExited: exitCode => {
            if (exitCode === 0) {
                pluginApi.pluginSettings.user = root.user;
                pluginApi.saveSettings();
            }
            repoProcess.running = true;
        }
    }
    Process {
        id: repoProcess

        command: platform === 'gitlab' ? ["glab", "repo", "list", "--output", "json"] : ["gh", "repo", "list", "--no-archived", "--json", "name"]
        running: false

        stdout: SplitParser {
            onRead: data => {
                try {
                    const repos = JSON.parse(data);
                    const list = [];
                    for (let i = 0; i < repos.length; i++) {
                        list.push({
                            name: repos[i].name,
                            key: repos[i].name
                        });
                    }
                    root.repoList = list;
                } catch (e) {
                    Logger.e(e.message);
                }
            }
        }

        onExited: exitCode => {
            if (exitCode === 0) {
                pluginApi.pluginSettings.repoList = root.repoList;
                pluginApi.saveSettings();
            }
            issueProcess.running = true;
            prProcess.running = true;
        }
    }
    Process {
        id: issueProcess

        command: platform === 'gitlab' ? ["glab", "issue", "list", "--repo", root.user.name + "/" + root.selectedRepo, "--assignee", "@me", "--opened", "--output", "json"] : ["gh", "search", "issues", "--repo", root.user.name + "/" + root.selectedRepo, "--assignee", "@me", "--state", "open", "--json", "title,number,state,body,author,assignees,labels"]
        running: false

        stdout: SplitParser {
            onRead: data => {
                try {
                    const parsed = JSON.parse(data);
                    root.issues = parsed.length === 0 ? "0" : parsed.length;
                } catch (e) {
                    Logger.e(e.message);
                }
            }
        }

        onExited: exitCode => {
            if (exitCode === 0) {
                pluginApi.pluginSettings.issues = root.issues;
                pluginApi.saveSettings();
            }
        }
    }
    Process {
        id: prProcess

        command: platform === 'gitlab' ?
            ["glab", "mr", "list", "--repo", root.user.name + "/" + root.selectedRepo, "--assignee", "@me", "--opened", "--output", "json"] :
            ["gh", "search", "prs", "--repo", root.user.name + "/" + root.selectedRepo, "--assignee", "@me", "--state", "open", "--json", "title,number,state,body,author,assignees,labels"]
        running: false

        stdout: SplitParser {
            onRead: data => {
                try {
                    const parsed = JSON.parse(data);
                    root.prs = parsed.length === 0 ? "0" : parsed.length;
                } catch (e) {
                    Logger.e(e.message);
                }
            }
        }

        onExited: exitCode => {
            if (exitCode === 0) {
                pluginApi.pluginSettings.prs = root.prs;
                pluginApi.saveSettings();
            }
        }
    }
    Rectangle {
        id: panelContainer

        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            spacing: Style.marginL

            anchors {
                fill: parent
                margins: Style.marginL
            }

            // HEADER
            NBox {
                Layout.fillWidth: true
                implicitHeight: headerRow.implicitHeight + Style.margin2M

                RowLayout {
                    id: headerRow

                    anchors.fill: parent
                    anchors.margins: Style.marginM
                    spacing: Style.marginM

                    NIcon {
                        color: Color.mPrimary
                        icon: platform === 'gitlab' ? "brand-gitlab" : "brand-github"
                        pointSize: Style.fontSizeXXL
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginXXS

                        NText {
                            Layout.fillWidth: true
                            color: Color.mOnSurface
                            elide: Text.ElideRight
                            font.weight: Style.fontWeightBold
                            pointSize: Style.fontSizeL
                            text: "Git Companion"
                        }
                    }
                    NIconButton {
                        baseSize: Style.baseWidgetSize * 0.8
                        icon: "settings"
                        tooltipText: I18n.tr("common.settings")

                        onClicked: {
                            // Use panelOpenScreen to get the screen this panel is on
                            var screen = pluginApi?.panelOpenScreen;
                            if (screen && pluginApi?.manifest) {
                                Logger.i("HelloWorld", "Opening plugin settings on screen:", screen.name);
                                BarService.openPluginSettings(screen, pluginApi.manifest);
                            }
                        }
                    }
                    NIconButton {
                        baseSize: Style.baseWidgetSize * 0.8
                        icon: "close"
                        tooltipText: I18n.tr("common.close")

                        onClicked: {
                            pluginApi?.closePanel(pluginApi?.panelOpenScreen);
                        }
                    }
                }
            }
            NScrollView {
                id: gitScrollView

                Layout.fillHeight: true
                Layout.fillWidth: true
                gradientColor: Color.mSurface
                horizontalPolicy: ScrollBar.AlwaysOff
                reserveScrollbarSpace: false
                verticalPolicy: ScrollBar.AsNeeded

                ColumnLayout {
                    id: mainColumn

                    spacing: Style.marginM
                    width: gitScrollView.availableWidth

                    // Error message
                    NBox {
                        id: erroBox

                        Layout.fillWidth: true
                        Layout.preferredHeight: emptyColumn.implicitHeight + Style.margin2M
                        visible: !root.isBinInstalled || !root.isAuthenticated

                        // Error Title
                        ColumnLayout {
                            id: emptyColumn

                            anchors.fill: parent
                            anchors.margins: Style.marginM
                            spacing: Style.marginL

                            NIcon {
                                Layout.alignment: Qt.AlignHCenter
                                color: Color.mOnSurfaceVariant
                                icon: "user-exclamation"
                                pointSize: 48
                            }
                            NText {
                                Layout.fillWidth: true
                                color: Color.mOnSurfaceVariant
                                horizontalAlignment: Text.AlignHLeft
                                pointSize: Style.fontSizeL
                                text: !root.isBinInstalled ? bin + " is not installed. Please install it to use this plugin." : bin + " is not authenticated. Run '" + bin + " auth login' to authenticate."
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    // User info
                    NBox {
                        id: userBox

                        Layout.fillWidth: true
                        Layout.preferredHeight: userColumn.implicitHeight + Style.margin2M
                        visible: root.isBinInstalled && root.isAuthenticated && !loading

                        ColumnLayout {
                            id: userColumn

                            anchors.fill: parent
                            anchors.margins: Style.marginM
                            spacing: Style.marginL

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.marginM

                                NImageRounded {
                                    Layout.alignment: Qt.AlignHCenter
                                    borderColor: Color.mPrimary
                                    borderWidth: 2
                                    fallbackIcon: "user"
                                    fallbackIconSize: 24
                                    height: Math.round(40 * Style.uiScaleRatio)
                                    imagePath: root.user.avatar
                                    radius: Math.min(Style.radiusL, width / 2)
                                    width: Math.round(40 * Style.uiScaleRatio)
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.marginXS

                                    NText {
                                        Layout.fillWidth: true
                                        color: Color.mOnSurface
                                        elide: Text.ElideRight
                                        font.weight: Font.Bold
                                        pointSize: Style.fontSizeM
                                        text: root.user.name
                                    }
                                    NText {
                                        Layout.fillWidth: true
                                        color: Color.mOnSurface
                                        elide: Text.ElideRight
                                        font.weight: Font.Thin
                                        pointSize: Style.fontSizeXS
                                        text: root.user.bio || "No bio"
                                    }
                                }
                                NIconButton {
                                    baseSize: Style.baseWidgetSize * 0.8
                                    icon: "refresh"
                                    tooltipText: pluginApi?.tr("panel.refresh")

                                    onClicked: startCheck()
                                }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginM
                        visible: !root.loading && root.isBinInstalled && root.isAuthenticated

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Style.marginS

                            NComboBox {
                                id: repoComboBox

                                Layout.fillWidth: true
                                currentKey: root.selectedRepo
                                description: "Select a repository to display"
                                label: "Repository"
                                model: root.repoList

                                onSelected: key => {
                                    pluginApi.pluginSettings.selectedRepo = key;
                                    pluginApi.saveSettings();
                                }
                            }
                        }
                    }

                    // Repository info
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginS
                        visible: !root.loading && root.isBinInstalled && root.isAuthenticated

                        ColumnLayout {
                            id: infoColumn

                            spacing: Style.marginS

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.marginM

                                NIcon {
                                    color: Color.mOnSurfaceVariant
                                    icon: "git-pull-request"
                                    pointSize: Style.fontSizeL
                                }
                                NText {
                                    color: Color.mOnSurfaceVariant
                                    font.pointSize: Style.fontSizeM
                                    text: root.prString + " (" + root.prs + ")"
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.marginM

                                NIcon {
                                    color: Color.mOnSurfaceVariant
                                    icon: "circle-dot"
                                    pointSize: Style.fontSizeL
                                }
                                NText {
                                    color: Color.mOnSurfaceVariant
                                    font.pointSize: Style.fontSizeM
                                    text: "Issues (" + root.issues + ")"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
