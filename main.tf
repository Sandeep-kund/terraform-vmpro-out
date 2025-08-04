resource "azurerm_resource_group" "rg1" {
  name     = "rg-resources"
  location = "westus2"
}

resource "azurerm_virtual_network" "rg1" {
  name                = "rg1-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg1.location
  resource_group_name = azurerm_resource_group.rg1.name
}

resource "azurerm_subnet" "rg1" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.rg1.name
  virtual_network_name = azurerm_virtual_network.rg1.name
  address_prefixes     = ["10.0.2.0/24"]


depends_on = [
    azurerm_virtual_network.rg1
  ]
}
resource "azurerm_network_interface" "rg1" {
  name                = "rg1-nic"
  location            = azurerm_resource_group.rg1.location
  resource_group_name = azurerm_resource_group.rg1.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.rg1.id
    private_ip_address_allocation = "Dynamic"
  }
    depends_on = [ azurerm_subnet.rg1 ]
}

 resource "azurerm_linux_virtual_machine" "rg1" {
  name                            = "rg1vm"
  resource_group_name             = azurerm_resource_group.rg1.name
  location                        = azurerm_resource_group.rg1.location
  size                            = "Standard_F2"
  admin_username                  = "adminuser"
  admin_password                  = "P@$$w0rd1234!"
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.rg1.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

resource "azurerm_automanage_configuration" "rg1" {
  name                = "rg1config"
  resource_group_name = azurerm_resource_group.rg1.name
  location            = azurerm_resource_group.rg1.location
}

resource "azurerm_virtual_machine_automanage_configuration_assignment" "rg1" {
  virtual_machine_id = azurerm_linux_virtual_machine.rg1.id
  configuration_id   = azurerm_automanage_configuration.rg1.id
}
