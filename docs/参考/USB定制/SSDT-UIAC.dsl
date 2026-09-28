DefinitionBlock ("", "SSDT", 2, "ACDT", "_UIAC", 0)
{
    Device(UIAC)
    {
        Name(_HID, "UIA00000")

        Name(RMCF, Package()
        {
            // XHCI (8086_1e31)
            "XHCI", Package()
            {
                "port-count", Buffer() { 0x06, 0x00, 0x00, 0x00 },
                "ports", Package()
                {
                    "HS01", Package()
                    {
                         "name", Buffer() { "HS01" },
                         "usb-port-type", 0,
                         "UsbConnector", 0,
                         "port", Buffer() { 0x01, 0x00, 0x00, 0x00 },
                         "usb-port-number", Buffer() { 0x01, 0x00, 0x00, 0x00 },
                    },
                    "HS02", Package()
                    {
                         "name", Buffer() { "HS02" },
                         "usb-port-type", 0,
                         "UsbConnector", 0,
                         "port", Buffer() { 0x02, 0x00, 0x00, 0x00 },
                         "usb-port-number", Buffer() { 0x02, 0x00, 0x00, 0x00 },
                    },
                    "SS01", Package()
                    {
                         "name", Buffer() { "SS01" },
                         "usb-port-type", 3,
                         "UsbConnector", 3,
                         "port", Buffer() { 0x05, 0x00, 0x00, 0x00 },
                         "usb-port-number", Buffer() { 0x05, 0x00, 0x00, 0x00 },
                    },
                    "SS02", Package()
                    {
                         "name", Buffer() { "SS02" },
                         "usb-port-type", 3,
                         "UsbConnector", 3,
                         "port", Buffer() { 0x06, 0x00, 0x00, 0x00 },
                         "usb-port-number", Buffer() { 0x06, 0x00, 0x00, 0x00 },
                    },
                },
            },
            // EH01 (8086_1e26)
            "EH01", Package()
            {
                "port-count", Buffer() { 0x01, 0x00, 0x00, 0x00 },
                "ports", Package()
                {
                    "PR11", Package()
                    {
                         "name", Buffer() { "PR11" },
                         "usb-port-type", 255,
                         "UsbConnector", 255,
                         "port", Buffer() { 0x01, 0x00, 0x00, 0x00 },
                         "usb-port-number", Buffer() { 0x01, 0x00, 0x00, 0x00 },
                    },
                },
            },
            // EH02 (8086_1e2d)
            "HUB2", Package()
            {
                "port-count", Buffer() { 0x06, 0x00, 0x00, 0x00 },
                "ports", Package()
                {
                    "HP22", Package()
                    {
                         "name", Buffer() { "HP22" },
                         "usb-port-type", 0,
                         "UsbConnector", 0,
                         "port", Buffer() { 0x02, 0x00, 0x00, 0x00 },
                         "usb-port-number", Buffer() { 0x02, 0x00, 0x00, 0x00 },
                    },
                    "HP23", Package()
                    {
                         "name", Buffer() { "HP23" },
                         "usb-port-type", 0,
                         "UsbConnector", 0,
                         "port", Buffer() { 0x03, 0x00, 0x00, 0x00 },
                         "usb-port-number", Buffer() { 0x03, 0x00, 0x00, 0x00 },
                    },
                    "HP24", Package()
                    {
                         "name", Buffer() { "HP24" },
                         "usb-port-type", 0,
                         "UsbConnector", 0,
                         "port", Buffer() { 0x04, 0x00, 0x00, 0x00 },
                         "usb-port-number", Buffer() { 0x04, 0x00, 0x00, 0x00 },
                    },
                    "HP26", Package()
                    {
                         "name", Buffer() { "HP26" },
                         "usb-port-type", 0,
                         "UsbConnector", 0,
                         "port", Buffer() { 0x06, 0x00, 0x00, 0x00 },
                         "usb-port-number", Buffer() { 0x06, 0x00, 0x00, 0x00 },
                    },
                },
            },
            // EH02 (8086_1e2d)
            "EH02", Package()
            {
                "port-count", Buffer() { 0x01, 0x00, 0x00, 0x00 },
                "ports", Package()
                {
                    "PR21", Package()
                    {
                         "name", Buffer() { "PR21" },
                         "usb-port-type", 255,
                         "UsbConnector", 255,
                         "port", Buffer() { 0x01, 0x00, 0x00, 0x00 },
                         "usb-port-number", Buffer() { 0x01, 0x00, 0x00, 0x00 },
                    },
                },
            },
        })
    }
}
