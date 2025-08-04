output "vm_public_ip" {
  value = azurerm_linux_virtual_machine.rg1.public_ip_address
}

output "vm_private_ip" {
  value = azurerm_network_interface.rg1.private_ip_address
}
