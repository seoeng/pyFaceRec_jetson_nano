#!/bin/bash
# ==============================================================================
# Jetson AI 출입문 시스템 자동 설치 스크립트 (Jetson Orin Nano 기준)
#
# 실행 방법:
# 1. 이 파일을 Jetson에 복사
# 2. 실행 권한 부여: chmod +x setup_jetson.sh
# 3. 스크립트 실행:   ./setup_jetson.sh
#
# (주의) JetPack OS는 미리 설치되어 있어야 합니다.
# ==============================================================================

# JetPack 6.0에 OpenCV 4.5.x+ 버전이 이미 설치 -> OpenCV 빌드 과정을 전부 삭제 가능

# --- [ 0단계: 기본 설정 ] ---

# (중요) 명령 하나라도 실패하면 즉시 스크립트를 중지
set -e

echo "Jetson AI 출입문 시스템 설치를 시작합니다..."
echo "이 작업은 수십 분 이상 소요될 수 있습니다. (특히 dlib/face_recognition)"


# --- [ 1단계: 시스템 기본 준비 (jtop 및 Swap) ] ---
# (두 번째 스크립트에서 가져온 필수 시스템 설정)

echo "[1/7] jtop (jetson-stats) 설치 중..."
sudo -H pip3 install -U jetson-stats

echo "[2/7] 4GB Swap 파일 생성 중... (메모리 부족 방지)"
if [ -f /var/swapfile ]; then
    echo "이미 /var/swapfile이 존재합니다. 생성을 건너뜁니다."
else
    sudo fallocate -l 4G /var/swapfile
    sudo chmod 600 /var/swapfile
    sudo mkswap /var/swapfile
    sudo swapon /var/swapfile
    sudo bash -c 'echo "/var/swapfile swap swap defaults 0 0" >> /etc/fstab'
    echo "Swap 파일 생성 및 fstab 등록 완료."
fi

# --- [ 2단계: APT 시스템 패키지 설치 ] ---
# (env_setup_guide.md의 3단계)

echo "[1/5] 시스템 업데이트 및 APT 패키지 설치 중..."

sudo apt-get update -y
sudo apt-get install -y python3-pip python3-dev

# GStreamer (오디오 재생 'snd_allowed'용)
# 만약 오디오 기능(출입 허가 음성)을 실제로 사용하지 않으신다면, door_lock_thread 코드에서 그 두 줄(snd_allowed = ... 와 os.system(snd_allowed))은 지우셔도 괜찮습니다.
# sudo apt-get install -y gstreamer1.0-tools gstreamer1.0-plugins-good gstreamer1.0-plugins-ugly gstreamer1.0-alsa

# Dlib / face_recognition 빌드 의존성
sudo apt-get install -y cmake
sudo apt-get install -y libopenblas-dev liblapack-dev
sudo apt-get install -y python3-opencv # JetPack 6.0에 OpenCV 4.5.x+ 버전이 이미 설치 -> OpenCV 빌드 과정을 전부 삭제 가능

echo "APT 패키지 설치 완료."

# --- [ 3단계: Google Coral (Edge TPU) 런타임 설치 ] ---
# (env_setup_guide.md의 4단계)

echo "[2/5] Google Coral (Edge TPU) 런타임 설치 중..."

# Google Coral APT 저장소 추가
# apt의 "주소록" 폴더(etc/apt/sources.list.d/)에 coral-edgetpu.list라는 새 주소 카드를 만들고, 그 카드 안에 "Google Coral 주소는 deb https://packages.cloud.google.com/apt ... 입니다."라고 적어 넣는 것
echo "deb https://packages.cloud.google.com/apt coral-edgetpu-stable main" | sudo tee /etc/apt/sources.list.d/coral-edgetpu.list

# Google APT 키 추가
# curl : 인터넷에서 파일 다운로드
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

# 저장소 목록 업데이트 및 런타임 설치
sudo apt-get update -y
sudo apt-get install -y libedgetpu1-std

echo "Edge TPU 런타임 설치 완료."

# --- [ 4단계: Python (pip) 라이브러리 설치 ] ---
# (env_setup_guide.md의 5단계)

echo "[3/5] Python (pip) 라이브러리 설치 중..."

# pip 및 기본 패키지 업그레이드
pip3 install --upgrade pip setuptools

# Wiegand 시리얼 통신
pip3 install pyserial

# Jetson GPIO 핀 제어
pip3 install Jetson.GPIO

# KNN 모델(.clf) 로드를 위한 scikit-learn
pip3 install scikit-learn

# Google Coral 라이브러리
pip3 install pycoral

# (가장 오래 걸리는 부분) dlib 및 face_recognition
echo "dlib 및 face_recognition 설치를 시작합니다."
echo "이 단계는 Jetson Orin Nano에서도 30분 이상 소요될 수 있습니다. 중단하지 마세요."
pip3 install dlib
pip3 install face_recognition

# NumPy는 대부분의 라이브러리와 함께 설치되지만, 확실히 하기 위해 명시
pip3 install numpy

echo "Python 라이브러리 설치 완료."

# --- [ 5단계: 사용자 권한 설정 ] ---

echo "[6/7] 시리얼(dialout) 및 GPIO 권한 설정 중..."

# pySerial (Wiegand)를 sudo 없이 사용하기 위함
sudo usermod -a -G dialout $USER

# Jetson.GPIO를 sudo 없이 사용하기 위함
sudo groupadd -f -r gpio
sudo usermod -a -G gpio $USER
# Jetson.GPIO용 udev 규칙 복사 (이미 있을 수 있지만 확인)
if [ ! -f /etc/udev/rules.d/99-gpio.rules ]; then
    echo "GPIO udev 규칙을 설정합니다..."
    # 이 규칙은 Jetson.GPIO 패키지 설치 시 자동으로 생성될 수 있으나,
    # 수동으로 보장하기 위해 깃에서 가져오는 방법도 있습니다.
    # 우선은 Jetson.GPIO 설치만으로 충분할 수 있으므로 이 부분은 필요시 주석 해제
    # (필요시)
    # cd /tmp
    # git clone https://github.com/NVIDIA/jetson-gpio.git
    # sudo cp jetson-gpio/lib/python/Jetson/GPIO/99-gpio.rules /etc/udev/rules.d/
    # cd ~
    # rm -rf /tmp/jetson-gpio
    echo "Jetson.GPIO 설치 시 udev 규칙이 자동으로 설정되기를 기대합니다."
    echo "만약 GPIO 권한 오류가 발생하면, 이 스크립트의 6단계를 확인하세요."
else
    echo "GPIO udev 규칙이 이미 존재합니다."
fi

# --- [ 6단계: 프로젝트 폴더 구조 생성 ] ---
# (env_setup_guide.md의 6단계)

echo "[4/5] 프로젝트 폴더 구조 생성 중..."

# (중요) 이 스크립트가 있는 위치 기준으로 폴더 생성
# -p 옵션: 폴더가 이미 있어도 오류를 내지 않음
mkdir -p models
mkdir -p media/Faces
mkdir -p Logs

echo "폴더 (models, media/Faces, Logs) 생성 완료."

# --- [ 6단계: 완료 및 수동 작업 안내 ] ---

echo "[5/5] 자동 설치 스크립트가 성공적으로 완료되었습니다!"
echo "--------------------------------------------------------"
echo "(중요) 다음 '수동' 작업을 완료해야 합니다:"
echo ""
echo "  1. [모델 복사]"
echo "     -> 'models/' 폴더 안에 다음 파일들을 복사하세요:"
echo "        - mobilenet_ssd_v2_face_quant_postprocess_edgetpu.tflite"
echo "        - trained_knn_model.clf"
echo ""
echo "  2. [미디어 파일 복사]"
echo "     -> 'media/' 폴더 안에 다음 파일들을 복사하세요:"
echo "        - allowed.ogg"
echo "     -> 'media/Faces/' 폴더 안에 사용자별 폴더를 만드세요:"
echo "        - (예: media/Faces/홍길동/face_ID.jpg)"
echo "        - (예: media/Faces/홍길동/cardID.txt)"
echo ""
echo "  3. [하드웨어 연결]"
echo "     -> Coral TPU, Wiegand 컨트롤러, GPIO 릴레이를 Jetson에 연결하세요."
echo ""
echo "  4. [재부팅 권장]"
echo "     -> 모든 드라이버가 올바르게 로드되도록 재부팅(sudo reboot)하는 것을 권장합니다."
echo ""
echo "설치 완료."

