#include <KStatusNotifierItem>
#include <QAction>
#include <QApplication>
#include <QClipboard>
#include <QColor>
#include <QDesktopServices>
#include <QIcon>
#include <QDialog>
#include <QLabel>
#include <QVBoxLayout>
#include <QDialogButtonBox>
#include <QSettings>
#include <QActionGroup>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMenu>
#include <QPainter>
#include <QPixmap>
#include <QProcess>
#include <QTimer>
#include <QUrl>

static QIcon tabletIcon(const QColor &color)
{
    QIcon icon;
    for (int size : {22, 32, 48, 64}) {
        QPixmap image(size, size);
        image.fill(Qt::transparent);
        QPainter painter(&image);
        painter.setRenderHint(QPainter::Antialiasing);
        painter.scale(size / 24.0, size / 24.0);
        painter.setPen(QPen(color, 1.8));
        painter.setBrush(Qt::NoBrush);
        painter.drawRoundedRect(QRectF(3, 2, 18, 20), 2, 2);
        painter.setPen(Qt::NoPen);
        painter.setBrush(color);
        painter.drawEllipse(QPointF(12, 19.5), 0.8, 0.8);
        icon.addPixmap(image);
    }
    return icon;
}

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    app.setApplicationName("iPad Display");
    app.setDesktopFileName("ipad-display-tray");
    app.setQuitOnLastWindowClosed(false);

    KStatusNotifierItem tray(QStringLiteral("ipad-display"), &app);
    tray.setTitle("iPad Display");
    tray.setCategory(KStatusNotifierItem::Hardware);
    tray.setStatus(KStatusNotifierItem::Active);
    tray.setStandardActionsEnabled(false);
    tray.setIsMenu(false);

    auto *menu = new QMenu;
    auto *state = menu->addAction("Checking services...");
    auto *ssidLabel = menu->addAction("Wi-Fi: checking...");
    auto *ipLabel = menu->addAction("IPv4: checking...");
    for (auto *action : {state, ssidLabel, ipLabel})
        action->setEnabled(false);
    menu->addSeparator();
    auto *toggle = menu->addAction("Toggle iPad display");
    auto *modeMenu = menu->addMenu("Connection mode (next start)");
    auto *modes = new QActionGroup(modeMenu);
    modes->setExclusive(true);
    QSettings settings("ipad-display", "tray");
    QString mode = settings.value("mode", "wifi").toString();
    if (mode != "wifi" && mode != "direct" && mode != "shared")
        mode = "wifi";
    for (const auto &entry : { qMakePair(QString("Existing Wi-Fi"), QString("wifi")),
                                qMakePair(QString("Dedicated Hotspot"), QString("direct")),
                                qMakePair(QString("Hotspot + Internet"), QString("shared")) }) {
        auto *action = modeMenu->addAction(entry.first);
        action->setCheckable(true);
        modes->addAction(action);
        action->setChecked(mode == entry.second);
        QObject::connect(action, &QAction::triggered, &app, [&, selected = entry.second] {
            mode = selected;
            settings.setValue("mode", mode);
        });
    }
    auto *apLabel = menu->addAction("Hotspot: off");
    auto *channelLabel = menu->addAction("Channel: unavailable");
    auto *internetLabel = menu->addAction("Internet sharing: off");
    for (auto *action : {apLabel, channelLabel, internetLabel})
        action->setEnabled(false);
    auto *qr = menu->addAction("Show hotspot Wi-Fi QR code");
    auto *copy = menu->addAction("Copy Moonlight host IP");
    auto *web = menu->addAction("Open Sunshine settings");
    tray.setContextMenu(menu);

    QProcess poll, command;
    QString ssid, ip, server, monitor, apIp, apSsid, apChannel, apInternet;
    QProcess qrProcess;
    bool busy = false, valid = false;
    auto render = [&] {
        const bool running = server == "active" && monitor == "active";
        const bool transition = server == "activating" || monitor == "activating" ||
                                server == "deactivating" || monitor == "deactivating";
        const bool partial = (server == "active") != (monitor == "active");
        const bool failed = server == "failed" || monitor == "failed";
        QString status = !valid ? "Status unavailable" :
                         busy || transition ? "Changing state..." :
                         running ? "Server running" :
                         partial || failed ? "Check services" : "Off";
        const QIcon icon = tabletIcon(busy || transition || partial || failed ? QColor("#d97706") :
                                     running ? QColor("#22c55e") : QColor("#9ca3af"));
        tray.setIconByPixmap(icon);
        const QString network = ssid.isEmpty() ? "Not connected" : ssid;
        const QString address = ip.isEmpty() ? "Unavailable" : ip;
        tray.setToolTip(icon, "iPad Display",
                        status.toHtmlEscaped() + "<br>Wi-Fi: " + network.toHtmlEscaped() +
                        "<br>IPv4: " + address.toHtmlEscaped() +
                        (apIp.isEmpty() ? QString() : "<br>Hotspot: " + apIp.toHtmlEscaped()));
        state->setText(status);
        // Ampersands are menu mnemonics; preserve literal SSID text.
        QString menuNetwork = network;
        ssidLabel->setText("Wi-Fi: " + menuNetwork.replace("&", "&&"));
        ipLabel->setText("IPv4: " + address);
        toggle->setText(running || partial ? "Stop iPad display" : "Start iPad display");
        toggle->setEnabled(valid && !busy && !transition);
        apLabel->setText(apIp.isEmpty() ? "Hotspot: off" : "Hotspot: " + apSsid + " (" + apIp + ")");
        channelLabel->setText(apChannel.isEmpty() ? "Channel: unavailable" : apChannel);
        internetLabel->setText("Internet sharing: " + (apInternet.isEmpty() ? QString("off") : apInternet));
        qr->setEnabled(valid && !busy && !apIp.isEmpty() && qrProcess.state() == QProcess::NotRunning);
        modeMenu->setEnabled(valid && !busy && !running && !partial && !transition && apIp.isEmpty());
        copy->setEnabled(valid && (!apIp.isEmpty() || !ip.isEmpty()));
        web->setEnabled(running);
    };

    auto refresh = [&] {
        if (!busy && poll.state() == QProcess::NotRunning)
            poll.start(QStringLiteral(IPAD_DISPLAY_CLI), {"info"});
    };
    QObject::connect(&poll, &QProcess::finished, &app, [&](int code, QProcess::ExitStatus status) {
        const auto data = QJsonDocument::fromJson(poll.readAllStandardOutput());
        valid = code == 0 && status == QProcess::NormalExit && data.isObject();
        if (valid) {
            const auto object = data.object();
            ssid = object.value("ssid").toString();
            ip = object.value("ipv4").toString();
            server = object.value("sunshine").toString();
            monitor = object.value("monitor").toString();
            const auto hotspot = object.value("hotspot").toObject();
            apIp = hotspot.value("ip").toString();
            apSsid = hotspot.value("ssid").toString();
            apChannel = hotspot.value("channel").toString();
            apInternet = hotspot.value("internet").toString();
        }
        render();
    });
    QObject::connect(&poll, &QProcess::errorOccurred, &app, [&](QProcess::ProcessError) {
        valid = false;
        render();
    });

    auto flip = [&] {
        if (!valid || busy || !toggle->isEnabled())
            return;
        busy = true;
        render();
        command.start(QStringLiteral(IPAD_DISPLAY_CLI), {"toggle", mode});
    };
    QObject::connect(toggle, &QAction::triggered, &app, flip);
    QObject::connect(&tray, &KStatusNotifierItem::activateRequested, &app,
                     [&](bool, const QPoint &) { flip(); });
    QObject::connect(copy, &QAction::triggered, &app, [&] {
        QApplication::clipboard()->setText(apIp.isEmpty() ? ip : apIp);
    });
    QObject::connect(qr, &QAction::triggered, &app, [&] {
        if (qrProcess.state() == QProcess::NotRunning) {
            qrProcess.start(QStringLiteral(IPAD_DISPLAY_CLI), {"qr"});
            qr->setEnabled(false);
        }
    });
    QObject::connect(&qrProcess, &QProcess::finished, &app, [&](int code, QProcess::ExitStatus status) {
        QPixmap image;
        if (code == 0 && status == QProcess::NormalExit &&
            image.loadFromData(qrProcess.readAllStandardOutput(), "PNG")) {
            auto *dialog = new QDialog;
            dialog->setAttribute(Qt::WA_DeleteOnClose);
            dialog->setWindowTitle("Join Gram-Display");
            auto *layout = new QVBoxLayout(dialog);
            auto *hint = new QLabel("Scan with the iPad Camera, then tap Join Network.\nMoonlight host: 10.42.0.1");
            hint->setTextFormat(Qt::PlainText);
            layout->addWidget(hint);
            auto *picture = new QLabel;
            picture->setPixmap(image);
            picture->setAlignment(Qt::AlignCenter);
            layout->addWidget(picture);
            auto *buttons = new QDialogButtonBox(QDialogButtonBox::Close);
            layout->addWidget(buttons);
            QObject::connect(buttons, &QDialogButtonBox::rejected, dialog, &QDialog::close);
            dialog->show();
            dialog->raise();
            dialog->activateWindow();
        } else {
            tray.showMessage("iPad Display", "Wi-Fi QR code unavailable.", "dialog-error");
        }
        render();
    });
    QObject::connect(&qrProcess, &QProcess::errorOccurred, &app, [&](QProcess::ProcessError) {
        render();
    });
    QObject::connect(web, &QAction::triggered, &app, [] {
        QDesktopServices::openUrl(QUrl("https://localhost:47990"));
    });
    QObject::connect(&command, &QProcess::finished, &app, [&](int code, QProcess::ExitStatus status) {
        const QString error = QString::fromUtf8(command.readAllStandardError()).trimmed();
        busy = false;
        valid = false;
        if (code != 0 || status != QProcess::NormalExit)
            tray.showMessage("iPad Display", error.isEmpty() ? "Toggle failed. Run ipad-display logs." : error.left(300), "dialog-error");
        render();
        refresh();
    });
    QObject::connect(&command, &QProcess::errorOccurred, &app, [&](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            busy = false;
            valid = false;
            tray.showMessage("iPad Display", "Could not launch the control command.", "dialog-error");
            render();
            refresh();
        }
    });
    QTimer timer;
    QObject::connect(&timer, &QTimer::timeout, &app, refresh);
    QObject::connect(menu, &QMenu::aboutToShow, &app, refresh);
    timer.start(5000);
    render();
    refresh();
    return app.exec();
}
