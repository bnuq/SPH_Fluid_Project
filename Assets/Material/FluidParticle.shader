Shader "Fluid/FluidParticle"
{
    Properties
    {

        // Ambient, 그냥 무조건 들어오는 색깔
            // Ambient Color
            _AmbientColor("Ambient Color", Color) = (0,0,1,1)

            //간접광을 얼마나 받을 지, ambient degree
            _AmbientDegree("Ambient Degree", Range(0, 1)) = 0.25


        // Diffuse, 반사돼서 들어오는 색깔
            // 노멀 벡터에 따른 광량을 체크한다
            // Diffuse Color
            _DiffuseColor("Diffuse Color", Color) = (0,0,1,1)

            // 난반사를 얼마나 받을 지
            _DiffuseDegree("Diffuse Degree", Range(0, 1)) = 0.25


        // Specular, 
            //반사광 색, 무채색을 가진다
            _SpecColor("Specular Color", Color) = (1, 1, 1, 1)

            //반사광을 적용하는 정도
            _SpecularDegree("Specular Degree", Range(0, 1)) = 0.5

            //스펙큘러 범위 조절
            _Shininess("Shininess", Range(0, 10)) = 10


        // 투명도 조절
            _AlphaValue("Alpha Value", Range(0, 1)) = 0.5

    }


    SubShader
    {
        //기본적인 알파 블렌딩 적용 => Fluid 이기 때문에, 투명함을 보이고 싶다
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            CGPROGRAM
                #pragma vertex vert
                #pragma fragment frag

                // 기본 헤더파일
                #include "UnityCG.cginc"
                
                // 라이팅 계산
                #include "UnityLightingCommon.cginc"
                

                // Properties
                    fixed4 _AmbientColor;
                    float _AmbientDegree;

                    fixed4 _DiffuseColor;
                    float _DiffuseDegree;


                    //fixed4 _SpecColor;
                    float _SpecularDegree;
                    float _Shininess;

                    float _AlphaValue;


                struct appdata
                {
                    float4 vertex : POSITION;   //Mesh 의 모델 정점 좌표

                    //모델의 노말 벡터를 사용하지 않고
                    //계산한 surface normal 을 이용해서 라이팅 계산을 할 것이다
                    // float3 normal : NORMAL;
                };


                struct v2f
                {
                    float4 vertexClip  : SV_POSITION;    //클립 공간의 정점 위치
                    float4 vertexWorld : TEXCOORD1;     //월드 공간에서의 정점 위치
                    
                    //월드 공간에서의, 물 표면 노멀벡터 -> 공기에서 물을 향한다
                    float3 surfaceNormalWorld : TEXCOORD2;

                    // 노멀 벡터의 크기
                    float surfaceNormalLength : SNL;
                };
              
                
                //Compute Buffer 를 통해 넘겨받는 Particle Struct 의 구조
                struct Particle
                {
                    float3 position;
                    float3 velocity;
                    float3 force;
                    float density;
                    float pressure;
                    float3 surfNormal;
                };
                StructuredBuffer<Particle> particles;


            //스크립트를 통해 넘겨받는 변수
                //그리려는 모델의 반지름
                float particleRadius;
                
                //표면과 내부를 구분하는 threshold
                float surfTrackThreshold;

                //fluid 의 영역
                float3 limitRange;



            //Vertex Shader
                //Mesh 를 이루는 정점에 대한 처리
                v2f vert (appdata v, uint instanceID : SV_InstanceID)
                {
                    v2f o;

                    //현재 정점이 속한 인스턴스인 Particle 의, 월드 공간에서의 위치를 가져온다
                    float3 pos = particles[instanceID].position;


                    // 월드 좌표계 => 모델 좌표계 월드 좌표, 일치 시키는 변환을
                    // 각 모델 정점에 적용 => 정점의 월드 좌표계를 얻을 수 있다
                    // 모델 좌표계의 정점을, 인스턴스가 위치한 위치로 보내는 이동변환을 만든다
                    // 그리고 주어진 radius 만큼 크기가 변하도록 확대변환도 추가한다
                    // 이동변환 + 확대변환
                    float4x4 affinMat = float4x4 (
                                                    particleRadius, 0, 0, pos.x,
                                                    0, particleRadius, 0, pos.y,
                                                    0, 0, particleRadius, pos.z,
                                                    0,0,0,1
                                                );

                    //모델의 정점에 이동변환을 적용한다 => 해당 위치에 Particle Instance 가 생기도록 한다
                    v.vertex = mul(affinMat, v.vertex);


                    /*
                        정점의 위치가 변했으니, 노멀벡터도 변환을 해주어야 한다

                        원래 노멀 벡터는, 노멀 정점과 다른 변환을 적용
                        [L | t] 변환 중,
                        linear transform 인 L 변환에 대해서 => (L ^ -1) ^ T 를 노멀 벡터에 적용
                        inverse transform 적용 => 후 normalize

                        근데 여기서는 모델 => 월드 변환 시, 회전이 없다 + uniform scaling
                        따라서 노멀 벡터를 변환하지 않고, 그냥 있던 것을 사용하면 된다
                     */
                    /*
                        근데 particle.surfNormal = 바깥에서 fluid 를 향하는 벡터 방향
                        흔히 정점의 노멀벡터라면 바깥을 향하는 방향
                        따라서 방향을 바꾸어 주어야 한다
                     */
                    float3 normalWorld = -particles[instanceID].surfNormal;


                    //v2f o 를 리턴한다
                    o.vertexWorld = v.vertex;
                    o.vertexClip = UnityWorldToClipPos(v.vertex);
                    
                    /*
                        노멀 벡터의 크기는 원래 라이팅에 중요하지 않다
                        하지만 여기서는 계산된 노멀벡터의 크기 => 경계 여부를 판단
                        따라서 크기를 저장해둔다
                     */
                    o.surfaceNormalWorld = normalWorld;
                    o.surfaceNormalLength = length(normalWorld);
                    


                    return o;
                }


                //Fragment Shader
                fixed4 frag (v2f i) : SV_Target
                {
                    // 계산된 노멀 벡터의 크기 판단
                    // 그냥 표면 파티클이 아니면 그리지 않는다
                    if(i.surfaceNormalLength < surfTrackThreshold) return fixed4(0, 0, 0, 0);


                // 1. Ambient Color
                    float3 AmbientTerm = (_AmbientColor.xyz) * _AmbientDegree;

                // 2. Diffuse Color
                    //프레그먼트의 월드 공간 좌표계에서 surface normal 을 구한다
                    float3 norVec = normalize(i.surfaceNormalWorld);
                    
                    //빛 벡터 = 해당 프레그먼트에서 광원을 바라보는 벡터
                    //월드 공간에서 빛 벡터를 구한다
                    float3 lightVec = normalize(UnityWorldSpaceLightDir(i.vertexWorld));

                    float3 DiffuseTerm = max(dot(norVec, lightVec), 0) * (_DiffuseColor.xyz) * _DiffuseDegree;
                    
                // 3. Specular Color

                    //뷰 벡터 = 해당 프레그먼트에서 카메라를 바라보는 벡터
                    //뷰 벡터를 월드 공간에서 구한다 (프레그먼트의 월드 공간 좌표를 넣어서 구할 수 있다)
                    float3 viewVec = normalize(UnityWorldSpaceViewDir(i.vertexWorld));

                    // 빛 반사 벡터 => 프레그먼트에서 반사된 빛이 나아가는 방향
                    float3 reflectVec = reflect(lightVec, norVec);

                    // 눈에 들어오는 빛의 양
                    float lightAmountOnEye = max(0, dot(viewVec, reflectVec));
                    
                    // 매끄러움 계산
                    float specular = pow(lightAmountOnEye, _Shininess);

                    // 정반사 빛
                    float3 SpecularTerm = specular * (_SpecColor.xyz) * _SpecularDegree;

                    // 최종 색깔
                    float4 TotalColor = float4(AmbientTerm + DiffuseTerm + SpecularTerm, 0);


                // 4. 투명도 결정
                // 
                    //표면의 정도를 나타내는 변수를 만들자
                    //이 값이 0 에 가까울수록 내부이며, 클수록 표면이다
                    float surfCoef = i.surfaceNormalLength - surfTrackThreshold;
                    
                    //표면일수록 불투명한 값을 가지게 하자
                    TotalColor.w = surfCoef * _AlphaValue;
                    
                    return TotalColor;
                }
            ENDCG
        }
    }
}
