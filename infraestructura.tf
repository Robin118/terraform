# Configure the Azure provider
terraform {

  required_version = ">=0.12"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>2.0" 
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "public_subnet" {
  name     = "Azure_Cloud"
  location = "eastus"
}

# Red Virtual
resource "azurerm_virtual_network" "network_cloud" {
  name                = "net_cloud"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.public_subnet.location
  resource_group_name = azurerm_resource_group.public_subnet.name
}


# SubNet Virtual Machine
resource "azurerm_subnet" "public_subnet" {
  name                 = "subnet_privatecloud"
  resource_group_name  = azurerm_resource_group.public_subnet.name
  virtual_network_name = azurerm_virtual_network.network_cloud.name
  address_prefixes     = ["10.0.2.0/24"]
}
#==========================================================================#
# SubNet Base de datos
resource "azurerm_subnet" "database_subnet" {

  address_prefixes     = ["10.0.1.0/24"]
  name                 = "subnet_database"
  resource_group_name  = azurerm_resource_group.public_subnet.name
  virtual_network_name = azurerm_virtual_network.network_cloud.name
  service_endpoints    = ["Microsoft.Storage"]

  delegation {
    name = "fs"

    service_delegation {
      name    = "Microsoft.DBforMySQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# Zona DNS bdd
resource "azurerm_private_bdd_dns" "bdd_dns" {

  name                = "database.robin.mysql.database.azure.com"
  resource_group_name = azurerm_resource_group.public_subnet.name
}

# Gestionar zonas DNS privadas
resource "azurerm_private_bdd_dns_virtual_network_link" "link_bdd_dns" {

  name                  = "mysqlRobin.com"
  private_bdd_dns_name = azurerm_private_bdd_dns.bdd_dns.name
  resource_group_name   = azurerm_resource_group.public_subnet.name
  virtual_network_id    = azurerm_virtual_network.network_cloud.id
}

#Gestiona el Servidor Flexible MySQL
resource "azurerm_mysql_flexible_server" "server_mysql" {

  location                     = azurerm_resource_group.public_subnet.location
  name                         = "server_database"
  resource_group_name          = azurerm_resource_group.public_subnet.name
  administrator_login          = "robin"
  administrator_password       = "Chevez2022.*"
  backup_retention_days        = 7
  delegated_subnet_id          = azurerm_subnet.database_subnet.id
  geo_redundant_backup_enabled = false
  private_bdd_dns_id          = azurerm_private_bdd_dns.bdd_dns.id
  sku_name                     = "GP_Standard_D2ds_v4"
  version                      = "8.0.21"
  zone                         = "1"

  high_availability {
    mode                      = "ZoneRedundant"
    standby_availability_zone = "2"
  }
  maintenance_window {
    day_of_week  = 0
    start_hour   = 8
    start_minute = 0
  }
  storage {
    iops    = 360
    size_gb = 20
  }

  depends_on = [azurerm_private_bdd_dns_virtual_network_link.link_bdd_dns]
}

# Gestiona la base de datos del Servidor Flexible MySQL
resource "azurerm_mysql_flexible_database" "database_wordpress" {
  charset             = "utf8"
  collation           = "utf8_unicode_ci"
  name                = "database_wordpress"
  resource_group_name = azurerm_resource_group.public_subnet.name
  server_name         = azurerm_mysql_flexible_server.server_mysql.name
}

#==========================================================================#

# IP Publica
resource "azurerm_public_ip" "public_subnet" {
  count               = 2
  name                = "publicIP-${count.index}"
  location            = azurerm_resource_group.public_subnet.location
  resource_group_name = azurerm_resource_group.public_subnet.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "webservices${count.index}"
}


# Interfaz de Red
resource "azurerm_network_interface" "public_subnet" {
  count               = 2
  name                = "network${count.index}"
  location            = azurerm_resource_group.public_subnet.location
  resource_group_name = azurerm_resource_group.public_subnet.name

  ip_configuration {
    name                          = "subnet_publicConfiguration"
    subnet_id                     = azurerm_subnet.public_subnet.id
    private_ip_address_allocation = "static"
    private_ip_address            = cidrhost("10.0.2.0/24", 4 + count.index)
    public_ip_address_id          = azurerm_public_ip.public_subnet[count.index].id
  }

}

# Crear y administrar discos de datos
resource "azurerm_managed_disk" "public_subnet" {
  count                = 2
  name                 = "disks_stock_${count.index}"
  location             = azurerm_resource_group.public_subnet.location
  resource_group_name  = azurerm_resource_group.public_subnet.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = "32"
}

# Agrupación de máquinas virtuales
resource "azurerm_availability_set" "avset" {
  name                         = "avset"
  location                     = azurerm_resource_group.public_subnet.location
  resource_group_name          = azurerm_resource_group.public_subnet.name
  platform_fault_domain_count  = 2
  platform_update_domain_count = 2
  managed                      = true
}


# Variable para el directorio de clave privada
variable "private_key_path" {
  type    = string
  default = "C:\\terraform\\claves\\private"
}

# Definir y configurar una máquina virtual 
resource "azurerm_virtual_machine" "public_subnet" {
  count                 = 2
  name                  = "vm_lms${count.index}"
  location              = azurerm_resource_group.public_subnet.location
  availability_set_id   = azurerm_availability_set.avset.id
  resource_group_name   = azurerm_resource_group.public_subnet.name
  network_interface_ids = [element(azurerm_network_interface.public_subnet.*.id, count.index)]
  vm_size               = "Standard_DS1_v2"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  # delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  # delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "myosdisk${count.index}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  # Optional data disks
  storage_data_disk {
    name              = "datadisk_new_${count.index}"
    managed_disk_type = "Standard_LRS"
    create_option     = "Empty"
    lun               = 0
    disk_size_gb      = "10"
  }

  storage_data_disk {
    name            = element(azurerm_managed_disk.public_subnet.*.name, count.index)
    managed_disk_id = element(azurerm_managed_disk.public_subnet.*.id, count.index)
    create_option   = "Attach"
    lun             = 1
    disk_size_gb    = element(azurerm_managed_disk.public_subnet.*.disk_size_gb, count.index)
  }

  os_profile {
    computer_name  = "Robin"
    admin_username = "robin"
    admin_password = "Chevez2022."
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  # Conexion Clave Privada
  connection {
    type        = "ssh"
    user        = "robin"
    password    = "Chevez2022."
    private_key = file(var.private_key_path)
    host        = azurerm_network_interface.public_subnet.id
  }

  tags = {
    environment = "staging"
  }
}


#crear grupo de seguridad y reglas de firewall

resource "azurerm_network_security_group" "security_rules" {
  name                = "rules_ssh"
  location            = azurerm_resource_group.public_subnet.location
  resource_group_name = azurerm_resource_group.public_subnet.name

  security_rule {
    name                       = "ssh_allow_rule"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "cms_lms"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "database_mysqll"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

#asociacion de grupo de seguridad con las maquinas virtuales existentes
resource "azurerm_network_interface_security_group_association" "association" {

  count = length(azurerm_network_interface.public_subnet)

  network_interface_id      = azurerm_network_interface.public_subnet[count.index].id
  network_security_group_id = azurerm_network_security_group.security_rules.id
}


#Sistema de monitoreo
#Logs por medio de consultas
resource "azurerm_log_analytics_workspace" "logs_cloudazure" {

  count = length(azurerm_network_interface.public_subnet)

  name                = "log-analytics-${count.index}"
  location            = azurerm_resource_group.public_subnet.location
  resource_group_name = azurerm_resource_group.public_subnet.name

  sku = "PerGB2018"
}

resource "azurerm_storage_account" "public_subnet" {

  count = length(azurerm_network_interface.public_subnet)

  name                     = "account_storage${count.index}"
  resource_group_name      = azurerm_resource_group.public_subnet.name
  location                 = azurerm_resource_group.public_subnet.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}


