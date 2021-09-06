#!/bin/bash


yum install docker git -y
systemctl start docker
systemctl enable docker
git clone https://github.com/Rohitkuru/cambium_networks.git
cd cambium_networks
docker build -t flask_app:latest .
docker run -d -p 5000:5000 flask_app:latest
