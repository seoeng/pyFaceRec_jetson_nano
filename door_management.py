# door_management.py (수정된 젯슨 보드용 - 스레드 버전)

import time
import Jetson.GPIO as GPIO
from parameters import GPIO_RELAY_PINS, LEDON_REMAIN_TIME

# 핀 설정: parameters.py의 핀 사용
# PIN 5: 도어 제어 릴레이 (DOOR_PIN)
# PIN 19: 인증 성공 LED (STATUS_LED_PIN)
DOOR_PIN = GPIO_RELAY_PINS[0] 
STATUS_LED_PIN = GPIO_RELAY_PINS[1] 

def init_gpio():
    """GPIO 초기 설정"""
    GPIO.setmode(GPIO.BOARD) # 핀 번호 기준 설정
    
    # 도어 및 LED 핀을 출력으로 설정하고 초기 LOW 상태로 설정 (도어 닫힘/LED 꺼짐)
    for pin in [DOOR_PIN, STATUS_LED_PIN]:
        GPIO.setup(pin, GPIO.OUT, initial=GPIO.LOW)
    
    print(f"[정보] GPIO 핀 초기화 완료. 도어 핀: {DOOR_PIN}, LED 핀: {STATUS_LED_PIN}")

def door_lock_thread(person_id_queue, led1_event, led2_event, led3_event, stop_event):
    """
    main.py에서 실행되는 도어 제어 스레드 함수
    인식된 ID를 받아 도어 릴레이와 LED를 제어합니다.
    """
    init_gpio()
    
    # 젯슨의 프로세스를 종료할 때 핀 정리를 위해 finally 블록 사용
    try:
        while not stop_event.is_set():
            # person_id_queue에서 ID를 기다림 (1초 타임아웃)
            try:
                person_id = person_id_queue.get(timeout=1)
            except:
                continue # 큐가 비어있으면 다시 대기
            
            # 'Unknown'이 아닌 ID가 들어왔다면 (인증 성공)
            if person_id != "Unknown":
                print(f"[인증 성공] {person_id} 님! 문을 엽니다.")
                
                # 1. LED 이벤트 발생 (예: video.py에서 화면 색상 변경)
                led1_event.set() 
                
                # 2. 상태 LED (GPIO) 켜기
                GPIO.output(STATUS_LED_PIN, GPIO.HIGH)
                
                # 3. 도어 릴레이 활성화 (문 열림)
                GPIO.output(DOOR_PIN, GPIO.HIGH)
                
                # 4. 설정된 시간만큼 대기 (문 열림 유지)
                time.sleep(LEDON_REMAIN_TIME)
                
                # 5. 도어 릴레이 비활성화 (문 닫힘)
                GPIO.output(DOOR_PIN, GPIO.LOW)
                
                # 6. 상태 LED 끄기
                GPIO.output(STATUS_LED_PIN, GPIO.LOW)
                
                # 7. LED 이벤트 리셋 (화면 상태 초기화)
                led1_event.clear()
            
            # Unknown ID의 경우 (인증 실패)
            elif person_id == "Unknown":
                # 필요한 경우 led2_event(실패 LED) 등을 여기서 처리할 수 있습니다.
                pass
                
    finally:
        # 프로세스 종료 시 GPIO 핀 초기화 (필수)
        GPIO.cleanup()
        print("[정보] door_lock_thread 종료 및 GPIO 초기화 완료.")

# 기존 단독 실행 코드는 삭제되었습니다.
