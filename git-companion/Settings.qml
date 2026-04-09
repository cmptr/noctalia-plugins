import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root

    property var cfg: pluginApi?.pluginSettings
    property var defaults: pluginApi?.manifest?.metadata?.defaultSettings
    property var pluginApi: null
    property string valuePlatform: cfg.platform ?? defaults.platform
    property int valueRefreshInterval: cfg.refreshInterval ?? defaults.refreshInterval

    function saveSettings() {
        if (!pluginApi) {
            Logger.e("HelloWorld", "Cannot save settings: pluginApi is null");
            return;
        }

        pluginApi.pluginSettings.platform = root.valuePlatform;
        pluginApi.pluginSettings.refreshInterval = root.valueRefreshInterval;
        pluginApi.saveSettings();

        Logger.d("HelloWorld", "Settings saved successfully");
    }

    spacing: Style.marginL

    Component.onCompleted: {
        Logger.d("HelloWorld", "Settings UI loaded");
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NComboBox {
            currentKey: root.valuePlatform
            description: pluginApi?.tr("settings.platform.desc")
            label: pluginApi?.tr("settings.platform.label")
            model: [
                {
                    "key": "github",
                    "name": "GitHub"
                },
                {
                    "key": "gitlab",
                    "name": "GitLab"
                }
            ]

            onSelected: key => {
                root.valuePlatform = key;
                pluginApi.pluginSettings.platform = key;
                pluginApi.saveSettings();
            }
        }
        NSpinBox {
            description: pluginApi?.tr("settings.refreshInterval.desc")
            label: pluginApi?.tr("settings.refreshInterval.label")
            stepSize: 1
            from: 30
            to: 90
            value: root.valueRefreshInterval

            onValueChanged: {
                root.valueRefreshInterval = value;
                pluginApi.pluginSettings.refreshInterval = value;
                pluginApi.saveSettings();
            }
        }
    }
}
