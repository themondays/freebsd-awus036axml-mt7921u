/*-
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright (c) 2026
 *
 * Experimental MediaTek MT79xx Bluetooth firmware loader for FreeBSD.
 *
 * This utility sends the MediaTek WMT firmware-download command flow over the
 * USB default control endpoint. It is intentionally small and currently tested
 * only with MT7961 Bluetooth function exposed by the AWUS036AXML.
 */

#include <sys/endian.h>
#include <sys/param.h>
#include <sys/stat.h>

#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <libusb.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define	DEFAULT_FW_DIR		"/usr/local/share/mtkbt-firmware"
#define	USB_TIMEOUT_MS		5000
#define	WMT_EVENT_TIMEOUT_MS	30000

#define	USB_MTK_VENDOR_ID	0x0e8d
#define	USB_MTK_MT7961_ID	0x7961

#define	HCI_CMD_WMT		0xfc6f
#define	HCI_EVENT_WMT		0xe4

#define	MTK_WMT_PATCH_DWNLD	0x01
#define	MTK_WMT_FUNC_CTRL	0x06

#define	MTK_WMT_PATCH_UNDONE	1
#define	MTK_WMT_PATCH_PROGRESS	2
#define	MTK_WMT_PATCH_DONE	3
#define	MTK_WMT_ON_UNDONE	4
#define	MTK_WMT_ON_DONE		5
#define	MTK_WMT_ON_PROGRESS	6

#define	MTK_PATCH_HDR_SIZE	32
#define	MTK_PATCH_GD_SIZE	64
#define	MTK_PATCH_SEC_MAP_SIZE	64
#define	MTK_PATCH_SEC_COMMON	12
#define	MTK_PATCH_SEC_SEND	52

#define	MTK_REG_DEV_ID		0x70010200
#define	MTK_REG_FW_VERSION	0x80021004
#define	MTK_REG_FW_FLAVOR	0x70010020
#define	MTK_EP_RST_OPT		0x74011890
#define	MTK_EP_RST_IN_OUT_OPT	0x00010001

static bool opt_debug;
static bool opt_info;

static void
usage(void)
{
	fprintf(stderr,
	    "usage: mtkbtfw [-DI] -d ugenX.Y [-f firmware-dir] [-F firmware-file]\n");
}

static void
info(const char *fmt, ...)
{
	va_list ap;

	if (!opt_info && !opt_debug)
		return;

	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
	fprintf(stderr, "\n");
}

static int
parse_ugen(const char *arg, int *busp, int *addrp)
{
	const char *p;
	char *endp;
	long bus, addr;

	p = strrchr(arg, '/');
	if (p != NULL)
		arg = p + 1;
	if (strncmp(arg, "ugen", 4) == 0)
		arg += 4;

	errno = 0;
	bus = strtol(arg, &endp, 10);
	if (errno != 0 || endp == arg || *endp != '.')
		return (-1);

	arg = endp + 1;
	errno = 0;
	addr = strtol(arg, &endp, 10);
	if (errno != 0 || endp == arg || *endp != '\0')
		return (-1);

	if (bus < 0 || bus > 255 || addr < 0 || addr > 255)
		return (-1);

	*busp = (int)bus;
	*addrp = (int)addr;
	return (0);
}

static libusb_device *
find_device(libusb_context *ctx, int bus, int addr)
{
	libusb_device **list;
	libusb_device *found;
	ssize_t count, i;

	found = NULL;
	count = libusb_get_device_list(ctx, &list);
	if (count < 0)
		errx(1, "libusb_get_device_list: %s",
		    libusb_strerror((int)count));

	for (i = 0; i < count; i++) {
		libusb_device *dev;
		struct libusb_device_descriptor desc;
		int error;

		dev = list[i];
		if (libusb_get_bus_number(dev) != bus ||
		    libusb_get_device_address(dev) != addr)
			continue;

		error = libusb_get_device_descriptor(dev, &desc);
		if (error != 0)
			errx(1, "libusb_get_device_descriptor: %s",
			    libusb_strerror(error));

		if (desc.idVendor != USB_MTK_VENDOR_ID ||
		    desc.idProduct != USB_MTK_MT7961_ID)
			errx(1, "ugen%d.%d is %04x:%04x, not MediaTek MT7961",
			    bus, addr, desc.idVendor, desc.idProduct);

		found = libusb_ref_device(dev);
		break;
	}

	libusb_free_device_list(list, 1);
	return (found);
}

static int
usb_reg_read(libusb_device_handle *h, uint32_t reg, uint32_t *valp)
{
	uint8_t buf[4];
	int n;

	n = libusb_control_transfer(h, 0xc0, 0x63, reg >> 16,
	    reg & 0xffff, buf, sizeof(buf), USB_TIMEOUT_MS);
	if (n != (int)sizeof(buf))
		return (n < 0 ? n : LIBUSB_ERROR_IO);

	*valp = le32dec(buf);
	return (0);
}

static int
usb_uhw_reg_write(libusb_device_handle *h, uint32_t reg, uint32_t val)
{
	uint8_t buf[4];
	int n;

	le32enc(buf, val);
	n = libusb_control_transfer(h, 0x5e, 0x02, reg >> 16,
	    reg & 0xffff, buf, sizeof(buf), USB_TIMEOUT_MS);
	if (n != (int)sizeof(buf))
		return (n < 0 ? n : LIBUSB_ERROR_IO);

	return (0);
}

static const char *
status_name(int status)
{
	switch (status) {
	case MTK_WMT_PATCH_UNDONE:
		return ("patch-undone");
	case MTK_WMT_PATCH_PROGRESS:
		return ("patch-progress");
	case MTK_WMT_PATCH_DONE:
		return ("patch-done");
	case MTK_WMT_ON_UNDONE:
		return ("function-off");
	case MTK_WMT_ON_DONE:
		return ("function-on");
	case MTK_WMT_ON_PROGRESS:
		return ("function-progress");
	default:
		return ("unknown");
	}
}

static int
wmt_recv_event(libusb_device_handle *h, uint8_t op, int *statusp)
{
	uint8_t evt[64];
	int elapsed_us, n;

	for (elapsed_us = 0; elapsed_us < WMT_EVENT_TIMEOUT_MS * 1000;
	    elapsed_us += 500) {
		memset(evt, 0, sizeof(evt));
		n = libusb_control_transfer(h, 0xc0, 0x01, 48, 0, evt,
		    sizeof(evt), 100);
		if (n == 0 || n == LIBUSB_ERROR_TIMEOUT) {
			usleep(500);
			continue;
		}
		if (n < 0)
			return (n);
		if (n < 7 || evt[0] != HCI_EVENT_WMT || evt[3] != op) {
			if (opt_debug) {
				fprintf(stderr, "unexpected WMT event:");
				for (int i = 0; i < n; i++)
					fprintf(stderr, " %02x", evt[i]);
				fprintf(stderr, "\n");
			}
			usleep(500);
			continue;
		}

		switch (op) {
		case MTK_WMT_PATCH_DWNLD:
			if (evt[6] == 2)
				*statusp = MTK_WMT_PATCH_DONE;
			else if (evt[6] == 1)
				*statusp = MTK_WMT_PATCH_PROGRESS;
			else
				*statusp = MTK_WMT_PATCH_UNDONE;
			break;
		case MTK_WMT_FUNC_CTRL:
			if (n >= 9) {
				uint16_t be_status;

				be_status = ((uint16_t)evt[7] << 8) | evt[8];
				if (be_status == 0x0404)
					*statusp = MTK_WMT_ON_DONE;
				else if (be_status == 0x0420)
					*statusp = MTK_WMT_ON_PROGRESS;
				else
					*statusp = MTK_WMT_ON_UNDONE;
			}
			break;
		default:
			break;
		}

		if (opt_debug) {
			fprintf(stderr, "WMT event:");
			for (int i = 0; i < n; i++)
				fprintf(stderr, " %02x", evt[i]);
			fprintf(stderr, "\n");
		}
		return (0);
	}

	return (LIBUSB_ERROR_TIMEOUT);
}

static int
wmt_sync(libusb_device_handle *h, uint8_t op, uint8_t flag,
    const void *payload, size_t payload_len, int *statusp)
{
	uint8_t buf[3 + 4 + 255];
	size_t hci_len, wmt_len;
	int n, status;

	if (payload_len > 250)
		return (LIBUSB_ERROR_INVALID_PARAM);

	wmt_len = 5 + payload_len;
	hci_len = 3 + wmt_len;

	le16enc(buf, HCI_CMD_WMT);
	buf[2] = (uint8_t)wmt_len;
	buf[3] = 1;
	buf[4] = op;
	le16enc(buf + 5, payload_len + 1);
	buf[7] = flag;
	if (payload_len != 0)
		memcpy(buf + 8, payload, payload_len);

	n = libusb_control_transfer(h, 0x20, 0x00, 0, 0, buf, hci_len,
	    USB_TIMEOUT_MS);
	if (n != (int)hci_len)
		return (n < 0 ? n : LIBUSB_ERROR_IO);

	status = 0;
	n = wmt_recv_event(h, op, &status);
	if (n != 0)
		return (n);

	if (statusp != NULL)
		*statusp = status;

	info("WMT op 0x%02x flag %u -> %s", op, flag, status_name(status));
	return (0);
}

static uint8_t *
read_firmware(const char *path, size_t *sizep)
{
	struct stat st;
	uint8_t *buf;
	ssize_t done;
	int fd;

	fd = open(path, O_RDONLY);
	if (fd < 0)
		err(1, "%s", path);
	if (fstat(fd, &st) != 0)
		err(1, "fstat %s", path);
	if (st.st_size < MTK_PATCH_HDR_SIZE + MTK_PATCH_GD_SIZE)
		errx(1, "%s is too small to be a MT79xx BT patch", path);

	buf = malloc(st.st_size);
	if (buf == NULL)
		err(1, "malloc firmware");

	done = read(fd, buf, st.st_size);
	if (done != st.st_size)
		err(1, "read %s", path);

	close(fd);
	*sizep = (size_t)st.st_size;
	return (buf);
}

static int
send_firmware(libusb_device_handle *h, const uint8_t *fw, size_t fw_len)
{
	uint32_t section_num;

	section_num = le32dec(fw + MTK_PATCH_HDR_SIZE + 12);
	if (section_num == 0 || section_num > 64)
		errx(1, "invalid firmware section count: %u", section_num);

	for (uint32_t i = 0; i < section_num; i++) {
		const uint8_t *map, *ptr;
		uint8_t cmd[1 + MTK_PATCH_SEC_SEND];
		uint32_t section_offset, dl_size;
		size_t map_offset, remaining;
		bool first;
		int error, retry, status;

		map_offset = MTK_PATCH_HDR_SIZE + MTK_PATCH_GD_SIZE +
		    MTK_PATCH_SEC_MAP_SIZE * i;
		if (map_offset + MTK_PATCH_SEC_MAP_SIZE > fw_len)
			errx(1, "firmware section map %u outside file", i);

		map = fw + map_offset;
		section_offset = le32dec(map + 4);
		dl_size = le32dec(map + 16);
		if (dl_size == 0)
			continue;
		if ((uint64_t)section_offset + dl_size > fw_len)
			errx(1, "firmware section %u outside file", i);

		info("section %u offset=%u size=%u", i, section_offset,
		    dl_size);

		cmd[0] = 0;
		memcpy(cmd + 1, map + MTK_PATCH_SEC_COMMON,
		    MTK_PATCH_SEC_SEND);

		for (retry = 20; retry > 0; retry--) {
			status = 0;
			error = wmt_sync(h, MTK_WMT_PATCH_DWNLD, 0, cmd,
			    sizeof(cmd), &status);
			if (error != 0)
				return (error);
			if (status == MTK_WMT_PATCH_UNDONE)
				break;
			if (status == MTK_WMT_PATCH_DONE)
				goto next_section;
			if (status != MTK_WMT_PATCH_PROGRESS)
				return (LIBUSB_ERROR_IO);
			usleep(100000);
		}
		if (retry == 0)
			return (LIBUSB_ERROR_TIMEOUT);

		ptr = fw + section_offset;
		remaining = dl_size;
		first = true;
		while (remaining > 0) {
			size_t chunk;
			uint8_t flag;

			chunk = remaining > 250 ? 250 : remaining;
			if (first) {
				flag = 1;
				first = false;
			} else if (remaining == chunk) {
				flag = 3;
			} else {
				flag = 2;
			}

			status = 0;
			error = wmt_sync(h, MTK_WMT_PATCH_DWNLD, flag, ptr,
			    chunk, &status);
			if (error != 0)
				return (error);
			if (status == MTK_WMT_PATCH_PROGRESS)
				return (LIBUSB_ERROR_IO);

			ptr += chunk;
			remaining -= chunk;
		}

next_section:
		continue;
	}

	usleep(120000);
	return (0);
}

int
main(int argc, char **argv)
{
	const char *device_arg, *fw_dir, *fw_path_arg;
	char fw_path[PATH_MAX];
	libusb_context *ctx;
	libusb_device *dev;
	libusb_device_handle *handle;
	uint8_t *fw;
	size_t fw_len;
	uint32_t dev_id, fw_version, fw_flavor;
	int bus, addr, ch, error, status;
	uint8_t enable;

	device_arg = NULL;
	fw_dir = DEFAULT_FW_DIR;
	fw_path_arg = NULL;

	while ((ch = getopt(argc, argv, "d:f:F:DIh")) != -1) {
		switch (ch) {
		case 'd':
			device_arg = optarg;
			break;
		case 'f':
			fw_dir = optarg;
			break;
		case 'F':
			fw_path_arg = optarg;
			break;
		case 'D':
			opt_debug = true;
			opt_info = true;
			break;
		case 'I':
			opt_info = true;
			break;
		case 'h':
		default:
			usage();
			return (ch == 'h' ? 0 : 2);
		}
	}

	if (device_arg == NULL) {
		usage();
		return (2);
	}
	if (parse_ugen(device_arg, &bus, &addr) != 0)
		errx(1, "invalid ugen device: %s", device_arg);

	error = libusb_init(&ctx);
	if (error != 0)
		errx(1, "libusb_init: %s", libusb_strerror(error));

	dev = find_device(ctx, bus, addr);
	if (dev == NULL)
		errx(1, "ugen%d.%d not found", bus, addr);

	error = libusb_open(dev, &handle);
	libusb_unref_device(dev);
	if (error != 0)
		errx(1, "libusb_open ugen%d.%d: %s", bus, addr,
		    libusb_strerror(error));

	error = usb_reg_read(handle, MTK_REG_DEV_ID, &dev_id);
	if (error != 0)
		errx(1, "read device id: %s", libusb_strerror(error));
	error = usb_reg_read(handle, MTK_REG_FW_VERSION, &fw_version);
	if (error != 0)
		errx(1, "read firmware version: %s", libusb_strerror(error));
	error = usb_reg_read(handle, MTK_REG_FW_FLAVOR, &fw_flavor);
	if (error != 0)
		errx(1, "read firmware flavor: %s", libusb_strerror(error));

	fw_flavor = (fw_flavor & 0x80) >> 7;
	info("dev_id=0x%04x fw_version=0x%08x fw_flavor=%u", dev_id,
	    fw_version, fw_flavor);

	if (dev_id != 0x7961)
		errx(1, "unsupported MediaTek BT device id 0x%04x", dev_id);

	if (fw_path_arg != NULL) {
		strlcpy(fw_path, fw_path_arg, sizeof(fw_path));
	} else if (fw_flavor != 0) {
		snprintf(fw_path, sizeof(fw_path),
		    "%s/BT_RAM_CODE_MT%04x_1a_%x_hdr.bin", fw_dir,
		    dev_id & 0xffff, (fw_version & 0xff) + 1);
	} else {
		snprintf(fw_path, sizeof(fw_path),
		    "%s/BT_RAM_CODE_MT%04x_1_%x_hdr.bin", fw_dir,
		    dev_id & 0xffff, (fw_version & 0xff) + 1);
	}

	fw = read_firmware(fw_path, &fw_len);
	info("loading %s (%zu bytes)", fw_path, fw_len);

	error = send_firmware(handle, fw, fw_len);
	free(fw);
	if (error != 0)
		errx(1, "firmware download failed: %s",
		    libusb_strerror(error));

	error = usb_uhw_reg_write(handle, MTK_EP_RST_OPT,
	    MTK_EP_RST_IN_OUT_OPT);
	if (error != 0)
		errx(1, "write endpoint reset option: %s",
		    libusb_strerror(error));

	enable = 1;
	status = 0;
	error = wmt_sync(handle, MTK_WMT_FUNC_CTRL, 0, &enable,
	    sizeof(enable), &status);
	if (error != 0)
		errx(1, "enable Bluetooth protocol: %s",
		    libusb_strerror(error));

	info("Bluetooth protocol enable status: %s", status_name(status));
	libusb_close(handle);
	libusb_exit(ctx);
	return (0);
}
