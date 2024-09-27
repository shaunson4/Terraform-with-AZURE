terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.1.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "a4c2f38b-78ba-42c2-8ff5-c618899339c5"
}

resource "azurerm_resource_group" "mtclab-rg" {
  name     = "mtclab-resources"
  location = "East Us"
  tags = {
    environment = "dev"
  }
}

resource "azurerm_virtual_network" "mtclab-vn" {
  name                = "mtclab-network"
  resource_group_name = azurerm_resource_group.mtclab-rg.name
  location            = azurerm_resource_group.mtclab-rg.location
  address_space       = ["10.123.0.0/16"]

  tags = {
    environment = "dev"
  }
}

resource "azurerm_subnet" "mtclab-subnet" {
  name                 = "mtclab-subnet"
  resource_group_name  = azurerm_resource_group.mtclab-rg.name
  virtual_network_name = azurerm_virtual_network.mtclab-vn.name
  address_prefixes     = ["10.123.1.0/24"]
}

resource "azurerm_network_security_group" "mtclab-sg" {
  name                = "mtclab-sg"
  location            = azurerm_resource_group.mtclab-rg.location
  resource_group_name = azurerm_resource_group.mtclab-rg.name

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_security_rule" "mtclab-dev-rule" {
  name                        = "mtclab-dev-rule"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.mtclab-rg.name
  network_security_group_name = azurerm_network_security_group.mtclab-sg.name
}

resource "azurerm_subnet_network_security_group_association" "mtclab-sga" {
  subnet_id                 = azurerm_subnet.mtclab-subnet.id
  network_security_group_id = azurerm_network_security_group.mtclab-sg.id
}

resource "azurerm_public_ip" "mtclab-ip" {
  name                = "mtclab-ip"
  resource_group_name = azurerm_resource_group.mtclab-rg.name
  location            = azurerm_resource_group.mtclab-rg.location
  allocation_method   = "Dynamic"
  sku                 = "Basic"

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_interface" "mtclab-nic" {
  name                = "mtclab-nic"
  location            = azurerm_resource_group.mtclab-rg.location
  resource_group_name = azurerm_resource_group.mtclab-rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.mtclab-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.mtclab-ip.id
  }

  tags = {
    environment = "dev"
  }
}

resource "azurerm_linux_virtual_machine" "mtclab-vm" {
  name                  = "mtclab-vm"
  resource_group_name   = azurerm_resource_group.mtclab-rg.name
  location              = azurerm_resource_group.mtclab-rg.location
  size                  = "Standard_B1s"
  admin_username        = "adminuser"
  network_interface_ids = [azurerm_network_interface.mtclab-nic.id]

  custom_data = filebase64("customdata.tpl")

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/mtclabazurekey.pub")
  }



  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"

  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"

  }
  provisioner "local-exec" {
    command = templatefile("${var.host_os}-ssh-script.tpl", {
      hostname     = self.public_ip_address,
      user         = "adminuser",
      identityfile = "~/.ssh/mtclabazurekey"
    })
    interpreter = var.host_os == "windows" ? ["Powershell", "-Command"] : ["bash", "-c"]
  }
}

data "azurerm_public_ip" "mtclab-ip-data"{
    name = azurerm_public_ip.mtclab-ip.name
    resource_group_name = azurerm_resource_group.mtclab-rg.name
}
output "public_ip_address" {
  value       = "${azurerm_linux_virtual_machine.mtclab-vm.name}: ${data.azurerm_public_ip.mtclab-ip-data.ip_address}"

}




