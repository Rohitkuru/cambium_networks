FROM python:3.6
RUN mkdir /app
COPY . /app
WORKDIR /app
RUN pip3 install -r requirement.txt
ENTRYPOINT ["python"]
CMD ["app.py"]
