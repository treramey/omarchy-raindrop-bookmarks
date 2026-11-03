#include <QCoreApplication>
#include <QImage>
#include <QImageReader>
#include <QImageWriter>
#include <QPainter>
#include <QSize>
#include <QByteArray>
#include <QFile>

#include <cstdio>

// This executable only receives local paths after cover-sync's download and MIME
// checks. Keep decoding in its own capped process, never inside Quickshell.
int main(int argc, char *argv[]) {
    QCoreApplication app(argc, argv);
    if (argc != 4) {
        std::fputs("cover thumbnail: expected format, input and output paths\n", stderr);
        return 1;
    }

    const QByteArray format(argv[1]);
    if (format != "png" && format != "jpeg" && format != "gif" && format != "webp") {
        std::fputs("cover thumbnail: unsupported format\n", stderr);
        return 1;
    }

    QFile input(QString::fromLocal8Bit(argv[2]));
    if (!input.open(QIODevice::ReadOnly)) return 1;
    QImageReader reader(&input, format);
    reader.setAutoDetectImageFormat(false);
    reader.setDecideFormatFromContent(false);
    reader.setAutoTransform(true);
    // size() parses the header before allocating the full pixel buffer.
    const QSize size = reader.size();
    if (!size.isValid() || size.width() > 8192 || size.height() > 8192 ||
        qint64(size.width()) * size.height() > 32 * 1024 * 1024) {
        std::fputs("cover thumbnail: invalid or oversized dimensions\n", stderr);
        return 1;
    }

    const QImage source = reader.read(); // First frame only, including animated formats.
    if (source.isNull() || source.width() > 8192 || source.height() > 8192 ||
        qint64(source.width()) * source.height() > 32 * 1024 * 1024) {
        std::fputs("cover thumbnail: image decode failed or exceeded dimensions\n", stderr);
        return 1;
    }

    QSize thumbnailSize = source.width() > 96 || source.height() > 96
        ? source.size().scaled(QSize(96, 96), Qt::KeepAspectRatio)
        : source.size();
    // Integer aspect scaling rounds the short axis to zero for images like 1x97.
    thumbnailSize.setWidth(qMax(1, thumbnailSize.width()));
    thumbnailSize.setHeight(qMax(1, thumbnailSize.height()));
    // Draw pixels into a fresh image so input text/EXIF metadata is never emitted.
    QImage pixels(thumbnailSize, QImage::Format_ARGB32);
    if (pixels.isNull()) return 1;
    {
        QPainter painter(&pixels);
        painter.setCompositionMode(QPainter::CompositionMode_Source);
        painter.setRenderHint(QPainter::SmoothPixmapTransform);
        painter.drawImage(QRect(QPoint(0, 0), thumbnailSize), source);
    }
    QImageWriter writer(QString::fromLocal8Bit(argv[3]), "png");
    if (!writer.write(pixels)) {
        std::fputs("cover thumbnail: PNG write failed\n", stderr);
        return 1;
    }
    return 0;
}
