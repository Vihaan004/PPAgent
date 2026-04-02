FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    ca-certificates \
    iverilog \
    yosys \
    python3 \
    python3-pip \
    python3-venv \
    git \
    curl \
    vim \
    gcc-riscv64-unknown-elf \
    && rm -rf /var/lib/apt/lists/*

# Use an image-local virtualenv so Python tools are isolated and predictable.
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

# Python deps for the benchmark harness and mini-swe-agent CLI.
RUN python -m pip install --upgrade pip setuptools wheel && \
    python -m pip install openai langchain langgraph mini-swe-agent

WORKDIR /workspace