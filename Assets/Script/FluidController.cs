using System.Collections;
using System.Collections.Generic;
using UnityEngine;


public class FluidController : MonoBehaviour
{
    #region Particle

        //Fluid 를 이루는 Particle 각각이 가지는 데이터
        private struct Particle
        {
            // 위치
            public Vector3 position;
            // 속도
            public Vector3 velocity;
            //particle 에 가해지는 힘 => 최소 3가지 요소로 구성되어 있다
            //압력 + 점성 + 표면장력
            public Vector3 force;
            
            // 밀도
            public float density;
            // 압력
            public float pressure;
                    
            //particle surface normal, 표면장력
            public Vector3 surfNormal;


            public Particle(Vector3 pos)
            {
                position = pos;
                velocity = Vector3.zero;
                force = Vector3.zero;
                density = 0.0f;
                pressure = 0.0f;
                surfNormal = Vector3.zero;
            }

        }
        
        //Particle Struct 의 크기
        int Particle_Size = 14 * sizeof(float);

        //사용하려는 전체 particle 의 개수 => 일력하는 particles 수에 의해 결정된다
        private int particleCount;

    #endregion

    #region 계산에 필요한 값들, 설정 값들

        //Particle 에 대한 정보
        [Header("Particle")]

            [Range(0.01f, 0.5f)]
            public float particleMass;         // particle 하나의 질량
            
            [Range(0.1f, 3.0f)]
            public float particleRadius;       // particle 하나의 반지름

            // particle 을 배치할 때, 한 줄에 몇개나 놓을 지, 생성하고자 하는 particle 갯수 지정
            [Min(2)]
            public int xNum;
            [Min(2)]
            public int yNum;
            [Min(2)]
            public int zNum;

            //Particle 들을 초기화할 때, 약간 섞어서 배치한다
            //이때 섞기 위해 랜덤 값으로 주는 seed
            [Range(0.1f, 0.5f)]
            public float seed;
       

        //Smooth Kerenl 에 대한 정보
        [Header("Kenrel")]

            /*
            Smooth Kernel 에서 사용하는 상수, core radius h
            SPH 방법에 의해서, 값을 보간할 때 계산에 포함시키는 거리를 의미한다
            떨어져 있는 거리가 h 이상이면, 영향을 주지 않는다, Smooth Kernel 값이 0 이다
            */
            [Range(0.1f, 3.0f)]
            public float smoothingRadius;

        
        //압력에 의한 힘 계산
        [Header("Pressure")]

            [Range(0.0f, 500.0f)]
            public float gasCoeffi;     //k, gas constant, 온도에 영향을 받는다, 온도가 높아지면 압력이 커진다

            [Range(0.0f, 1.0f)]
            public float restDensity;   //p_0, Make the simulation numerically more stable

        
        //점성에 의한 힘 계산
        [Header("Viscosity")]

            [Range(0.0f, 1.0f)]
            public float viscosity;     // 액체의 점성도


        //외력에 의한 힘 계산
        [Header("Gravity")]

            public Vector3 gravityAcel = new Vector3(0, -9.8f, 0); //기본 중력 가속도


        // 이동 계산
        [Header("DeltaTime")]

            //이동 계산에 사용할, 미소 시간, 델타 타임을 직접 지정한다
            public float deltaTime;

            //흐른 시간을 총 저장하는 변수
            private float totalTime = 0;


        // 범위 계산
        [Header("Limit Check")]

            // 공이 움직일 수 있는 범위
            public Vector3 limitRange;
            
            //경계와 충돌 후 속도가 줄어드는 정도, 마찰력
            [Range(0.01f, 0.7f)]
            public float damping;


        [Header("Wave")]

            [Range(0.0f, 40.0f)]
            public float extraForce; //파도를 만드는 외부 힘

        
        //표면 장력에 의한 힘
        [Header("Surface")]

            // 표면 장력의 정도를 결정하는 계수
            [Range(0.0f, 50.0f)]
            public float surfCoeffi;

            //표면 장력을 계산할지 말지 결정하는 임계값
            [Range(0.0f, 1.0f)]
            public float surfForceThreshold;

            //임의의 Particle 을 표면으로 취급할 지 말지를 결정하는 임계값
            [Range(0.0f, 1.0f)]
            public float surfTrackThreshold;

        
        //카메라 조작에 필요한 성분들
        [Header("MouseInput")]

            // 카메라 컴포넌트
            Camera cam;

            [Range(0.0f, 50.0f)]
            public float power;

            // 마우스가 클릭하는 위치를 저장
            // 스크린 공간에서의 점
            Vector2 fromPos = Vector2.zero;
            Vector2 toPos = Vector2.zero;

            // 입력받은 힘 벡터
            Vector2 inputForce = Vector2.zero;

            // 출발점과 도착점의 y 좌표 높이 비율을 저장하는 벡터
            Vector2 yRange = Vector2.zero;

    #endregion

    #region Buffer, Array 관련

        //particle 의 정보를 담는 배열
        Particle[] particleArray;
        
        //커널 실행에 필요한 그룹 수
        int groupSize;

        //배열의 크기
        int arraySize;

        //particle 정보를 GPU 로 넘겨주는 compute buffer
        ComputeBuffer particleBuffer;

    #endregion

    #region shader, material, kernel

        public ComputeShader shader;
        public Material material;       //fluid material

        int kernelComputeDensityPressure;   //힘을 계산하기 전, 각 Particles 의 밀도와 압력 값을 계산

        int kernelComputeForces;            //유체를 움직이는 힘 3가지를 계산
        int kernelComputeSurfaceForce;      //표면장력을 계산한다
        int kernelComputeInputForce;        //외부의 힘을 계산한다, 마우스 클릭을 통해서 힘을 가할 수 있다

        int kernelMakeMove;                 //계산된 힘에 맞춰서 이동
        int kernelCheckLimit;               //정해진 범위를 벗어나지 않게 한다



        // 클릭 시 힘을 주는 커널 <- 삭제 예정
        int kernelGiveForce;

    #endregion



    #region Indirect Draw 관련

    uint[] argsArray = { 0, 0, 0, 0, 0 };
        ComputeBuffer argsBuffer;
        Bounds bounds = new Bounds(Vector3.zero, Vector3.one * 0);


        // 그리려는 mesh
        public Mesh mesh = null;

    #endregion





    
    // 1. 가장 먼저 초기화를 진행한다
    void Start()
    {
        
        // 카메라 컴포너트 할당 => 메인 카메라를 사용한다
        cam = Camera.main;

        // 1-1. 커널들을 연결하고, 필요한 그룹 사이즈를 결정한다
        InitKernel();
        
        // 1-2. particle 들의 배열과 버퍼를 초기화 한다
        InitArrayAndBuffer();

        // 1-3. 셰이더, 머터리얼에서 필요한 값들을 모두 초기화 해준다
        SetPropertiesOnce();

    }





    // 2. 매 프레임마다 처리하는 일
    void Update()
    {        
        // Wave 진행을 위해, 실행 후 지난 시간을 compute shader 에 넣어주어야 한다
        // float 의 표현 범위가 10^31 까지 가능하기 때문에, overflow 는 걱정하지 않아도 된다
        totalTime += deltaTime;
        shader.SetFloat("Time", totalTime);

        /* 
            매 프레임, 시간마다 각 particle 의 밀도가 변하므로 밀도를 계산해 주어야 한다
            이후 밀도로 인한 각 particle 의 압력을 계산해주어야 한다
            그 다음에는 각 particle 에 가해지는 힘을 구해야 한다

            밀도 -> 압력 -> Forces

            알짜힘을 구했다면, 힘에 의한 가속도를 구하여서 새로운 속도를 구하고 새로운 속도로 이동한 위치를 구한다
            이후 해당 위치가 정해진 범위를 벗어나지 않게 하면 된다

            가속도 구하고 속도 갱신 위치 갱신 -> 범위 확인
        */
        // 2-1. 각 particle 들의 밀도와 압력을 먼저 계산하고
        shader.Dispatch(kernelComputeDensityPressure, groupSize, 1, 1);

        // 2-2. 각 particle 에 가해지는 힘을 계산한다
        shader.Dispatch(kernelComputeForces, groupSize, 1, 1);

        // 2-2-5. surface force 를 구하는 커널
        shader.Dispatch(kernelComputeSurfaceForce, groupSize, 1, 1);
        

        // 마우스 입력을 확인한다
            if(Input.GetMouseButtonDown(0))
            {
                fromPos = Input.mousePosition;

                // 출발점의 높이를 구한다
                yRange.x = fromPos.y / Screen.height;
            }

            if(Input.GetMouseButtonUp(0))
            {
                toPos = Input.mousePosition;

                // 도착점의 높이를 구한다
                yRange.y = toPos.y / Screen.height;

                // 출발점에서 도착점을 향하는 벡터를 구한다
                inputForce = toPos - fromPos;

                // 스크린 공간을 그대로 쓰면 너무 힘이 세니까, 조절한다
                // 오히려 너무 약한가??
                inputForce *= power;


                // yRange 넣기 전에, 더 작은 값이 x 에 오도록 한다
                if(yRange.x > yRange.y) 
                {
                    float temp = yRange.x;
                    yRange.x = yRange.y;
                    yRange.y = temp;
                }


                // compute shader 에 힘이 작용하는 범위와, 힘이 적용될 범위를 보낸다
                shader.SetVector("yRange", yRange);
                shader.SetVector("inputForce", inputForce);

                
                //마우스를 통해서 들어온 외부 힘을 계산
                shader.Dispatch(kernelComputeInputForce, groupSize, 1, 1);
            }








        
        // 모든 힘에 대한 처리를 끝마치고 나서 ~
        // 2-3. 가속도를 구하여서 새로운 속도, 위치를 구한다
        shader.Dispatch(kernelMakeMove, groupSize, 1, 1);

        // 2-4. 정해진 범위를 벗어나지 않았는 지 확인한다
        shader.Dispatch(kernelCheckLimit, groupSize, 1, 1);



        // 마지막으로 particle 들을 그려낸다
        Graphics.DrawMeshInstancedIndirect(mesh, 0, material, bounds, argsBuffer);


        /*
            <디버그용>
        
            Particle[] temp = new Particle[arraySize];
            particleBuffer.GetData(temp);
            Debug.Log("Index 0 is " + temp[0].surfNormal);
            Debug.Log("Index 560 is " + temp[560].surfNormal);
        */

        /* Particle[] temp = new Particle[arraySize];
        particleBuffer.GetData(temp);

        Debug.Log(temp[0].surfNormal); */

    }







    // 1-1. kernel 초기화
    void InitKernel()
    {
        
        // particle 의 밀도, 압력을 계산하는 커널
        kernelComputeDensityPressure = shader.FindKernel("ComputeDensityPressure");

        // 3 가지 종류의 힘의 합을 구하는 커널
        kernelComputeForces = shader.FindKernel("ComputeForces");
        
        // 가해진 힘을 바탕으로, 속도를 구하고 이동시킨다
        kernelMakeMove = shader.FindKernel("MakeMove");

        // 정해진 범위를 벗어나지 않게 하는 커널
        kernelCheckLimit = shader.FindKernel("CheckLimit");


        // 특정 영역에 있는 particle 들을 한 방향으로 힘을 가하는 커널
        kernelGiveForce = shader.FindKernel("GiveForce");


        // 표면 장력을 계산하는 커널
        kernelComputeSurfaceForce = shader.FindKernel("ComputeSurfaceForce");


        // 마우스 입력을 계산하는 커널
        kernelComputeInputForce = shader.FindKernel("ComputeInputForce");



        uint numThreadsX;
        // 한 커널의 스레드 그룹 수를 가져온다
        // 4 종류의 커널 모두 같은 사이즈의 스레드 그룹을 사용한다
        shader.GetKernelThreadGroupSizes(kernelComputeDensityPressure, out numThreadsX, out _, out _);


        // 채우고자 하는 갯수를 이용해서, 그리고자 하는 particle 전체 개수를 구한다
        particleCount = xNum * yNum * zNum;

        
        // 필요한 최소 그룹의 수
        groupSize = Mathf.CeilToInt((float)particleCount / (float)numThreadsX);

        
        // 모든 데이터를 담기 위해 필요한, 배열의 사이즈
        arraySize = (int)numThreadsX * groupSize;
        
    }



    // 1-2. 배열과 버퍼 초기화
    void InitArrayAndBuffer()
    {

        // particle 배열을 만들고 초기화 한다
        particleArray = new Particle[arraySize];

     
        /* 
            particle 들의 값들을 초기화 해서 담는다
            최대한 particle 들이 정해진 영역 내에서, 일정하게 나열되도록 한다
            그래야 처음에 particle 들이 세팅됐을 때, 지나치게 튕겨나가지 않는다
        */
        for (int i = 0; i < particleCount; i++)
        {
            
            Vector3 pos = new Vector3();

            /* 
                x -> y -> z 순서로 좌표값을 지정한다

                yNum * zNum 개가 하나의 plane 을 만들고, 이들은 모두 같은 x 좌표를 공유한다

                i / (yNum*zNum) => 몇 번째 plane 인지
                i % (yNum*zNum) => 하나의 plane 에서에서 몇 번째에 속하는 위치인지

                limitRange 범위 내에 particle 들을 담는다
                limitRange 내에서, xNum, yNum, zNum 개를 담도록 한다

                따라서 limitRange 에 의해 정해진 한 변을 xNum, yNum, zNum 으로 나눈 간격을 구해
                간격에 맞춰 일정하게 위치하도록 한다

                격자로 정해진 위치에서, 살짝 랜덤하게 변화를 주어, 쏟아지는 듯한 효과를 준다
            */
            pos.x = -limitRange.x + (i / (yNum * zNum)) * (2 * limitRange.x + 1)/(xNum - 1) + Random.Range(-seed, seed);

            pos.y = +limitRange.y - ( (i % (yNum * zNum)) / zNum ) * (2 * limitRange.y + 1) / (yNum - 1) + Random.Range(-seed, seed);

            pos.z = +limitRange.z - (i % zNum) * (2 * limitRange.z + 1) / (zNum - 1) + Random.Range(-seed, seed);


            // 초기화 한 particle 을 배열에 넣는다
            particleArray[i] = new Particle( pos );
        }



        // compute buffer 를 초기화 하고 배열 값을 넣는다
        particleBuffer = new ComputeBuffer(arraySize, Particle_Size);
        particleBuffer.SetData(particleArray);



        // Indirect Draw 를 위한 argument buffer 도 여기서 초기화 한다
        
        // mesh 의 시작 인덱스? 였나?
        argsArray[0] = mesh.GetIndexCount(0);
        // 그리고자 하는 instance 개수
        argsArray[1] = (uint)particleCount;

        argsBuffer = new ComputeBuffer(1, 5 * sizeof(uint), ComputeBufferType.IndirectArguments);
        argsBuffer.SetData(argsArray);

    }



    // 1-3. 한번만 초기화 해야 하는 값들을 넘긴다
    void SetPropertiesOnce()
    {

        // 가장 먼저 각 커널들에 compute buffer 를 넘겨준다
        shader.SetBuffer(kernelComputeDensityPressure, "particles", particleBuffer);
        shader.SetBuffer(kernelComputeForces, "particles", particleBuffer);
        shader.SetBuffer(kernelMakeMove, "particles", particleBuffer);
        shader.SetBuffer(kernelCheckLimit, "particles", particleBuffer);


        shader.SetBuffer(kernelGiveForce, "particles", particleBuffer);

        shader.SetBuffer(kernelComputeSurfaceForce, "particles", particleBuffer);


        // 마우스 입력 커널에 compute buffer 연결
        shader.SetBuffer(kernelComputeInputForce, "particles", particleBuffer);





        // particle 을 그리기 위한 material 에도 버퍼를 전달한다
        material.SetBuffer("particles", particleBuffer);



        // particle 에 대한 정보
            shader.SetFloat("particleMass", particleMass);
            shader.SetInt("particleCount", particleCount);

            material.SetFloat("particleRadius", particleRadius);

        
        // Smooth Kernel 에 대한 정보
            shader.SetFloat("h", smoothingRadius);
            shader.SetFloat("hSquare", smoothingRadius * smoothingRadius);

        

        // 압력 계산
            shader.SetFloat("gasCoeffi", gasCoeffi);
            shader.SetFloat("restDensity", restDensity);


        // 점성에 의한 힘 계산
            // 액체의 점성도
            shader.SetFloat("viscosity", viscosity);


        // 외력에 의한 힘 계산
            shader.SetVector("gravityAcel", gravityAcel);


        // 이동 계산
            // 시간 간격, 델타 타임
            shader.SetFloat("deltaTime", deltaTime);


        // 범위 계산
            // 공이 움직일 수 있는 범위
            // 입력받은 limitRange 를 사용한다 => particles 를 담을 크기
            // compute shader 에서는 limitRange 를 범위를 넘어간느 지를 확인하는 데 사용
            // 그러니까, 각 영역별로 1 씩 증가시켜서 넘기자
            shader.SetVector("limitRange", limitRange + new Vector3(1, 1, 1));

            material.SetVector("limitRange", limitRange + new Vector3(1, 1, 1));


            shader.SetFloat("damping", damping);



        // Wave 계산
            shader.SetFloat("extraForce", extraForce);


        // Surface
            shader.SetFloat("surfCoeffi", surfCoeffi);

            // compute shader 에서는 surface force 를 계산해야 하니까, 계산에 필요한 임계값이 필요하다
            shader.SetFloats("surfForceThreshold", surfForceThreshold);


            // 렌더링에서는 해당 particle 이 표면인지 아닌지를 구분해야 한다
            // 그리기 위해서 표면을 찾아야 하므로, surfTrackThreshold 값을 shader 에 넣어준다
            material.SetFloat("surfTrackThreshold", surfTrackThreshold);
            
    }


    

    // 1-4. 혹시 모르니까, 값이 변할 때마다 셰이더와 머터리얼에 할당해주는 값
    void SetProperties()
    {
        /* Particle */
            // 그려지는 particle 의 반지름
            material.SetFloat("particleRadius", particleRadius);


        /* Kernel */
            // smoothingRadius 변화
            shader.SetFloat("h", smoothingRadius);
            shader.SetFloat("hSquare", smoothingRadius * smoothingRadius);


        /* Pressure */
            shader.SetFloat("gasCoeffi", gasCoeffi);
            shader.SetFloat("restDensity", restDensity);


        /* Viscosity */
            // viscosity 변화
            shader.SetFloat("viscosity", viscosity);


        /* Wave */
            shader.SetFloat("extraForce", extraForce);


        /* Surface */
            shader.SetFloat("surfCoeffi", surfCoeffi);
            shader.SetFloats("surfForceThreshold", surfForceThreshold);

            material.SetFloat("surfTrackThreshold", surfTrackThreshold);

    }



    void OnValidate()
    {
        SetProperties();
    }





    
    // 파괴 시, 모든 compute buffer 삭제
    void OnDestroy()
    {
        particleBuffer.Dispose();
        argsBuffer.Dispose();
    }

}
