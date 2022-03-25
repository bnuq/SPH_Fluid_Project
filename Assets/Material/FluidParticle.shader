Shader "Fluid/FluidParticle"
{
    Properties
    {
        //Particle 이 자체적으로 가지는 색깔 => Fluid 니까 파란색을 생각
        _Color ( "Color", Color) = (0,0,1,1)

        //간접광을 얼마나 받을 지, ambient
        _Ambient ("Ambient", Range(0, 1)) = 0.25

        // diffuse 에 의한 알파를 조절
        _diffuseAlpha ( "Diffuse Alpha", Range(0,2)) = 1
        
        // 반사광 계산에 필요
        // 반사 광 색깔만 나타낼 것이기에, 물체는 무채색만 가진다
        _SpecColor ( "Specular Material Color", Color) = (1, 1, 1, 1) 

        _Shininess ( "Shininess", Range(0, 10)) = 10 // 스펙큘러 강도

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
                    fixed4 _Color;
                    float _Ambient;
                    float _diffuseAlpha;
                    float _Shininess;


                struct appdata
                {
                    float4 vertex : POSITION;   //Mesh 의 모델 정점 좌표

                    //모델의 노말 벡터를 사용하지 않고
                    //계산한 surface normal 을 이용해서 라이팅 계산을 할 것이다
                    // float3 normal : NORMAL;
                };

                struct v2f
                {
                    float4 vertexClip : SV_POSITION;    //클립 공간의 정점 위치
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

                    //모델 좌표계와 월드 좌표계가 동일하다고 생각
                    //모델 좌표계의 정점을, 인스턴스가 위치한 위치로 보내는 이동변환을 만든다
                    //그리고 주어진 radius 만큼 크기가 변하도록 확대변환도 추가한다
                    //이동변환 + 확대변환
                    float4x4 affinMat = float4x4 (
                                                    particleRadius, 0, 0, pos.x,
                                                    0, particleRadius, 0, pos.y,
                                                    0, 0, particleRadius, pos.z,
                                                    0,0,0,1
                                                );
                    //모델의 정점에 이동변환을 적용한다 => 해당 위치에 Particle Instance 가 생기도록 한다
                    v.vertex = mul(affinMat, v.vertex);


                    // 정점의 위치가 변했으니, 노멀벡터도 변환을 해주어야 한다
                    // 이동변환 외에, 균등 확대만 적용됐으므로 이를 노멀에 그대로 적용할 수 있다
                    float3x3 L = float3x3( 
                                            particleRadius, 0, 0,
                                            0, particleRadius, 0,
                                            0, 0, particleRadius
                                        );
                    /*
                        근데 particle.surfNormal = 바깥에서 fluid 를 향하는 벡터 방향
                        흔히 정점의 노멀벡터라면 바깥을 향하는 방향
                        따라서 방향을 바꾸어 주어야 한다
                    */
                    float3 normalWorld = mul( L, -particles[instanceID].surfNormal);


                    //v2f o 를 리턴한다
                    o.vertexWorld = v.vertex;
                    o.vertexClip = UnityWorldToClipPos(v.vertex);
                    
                    o.surfaceNormalWorld = normalWorld;
                    o.surfaceNormalLength = length(normalWorld);

                    return o;
                }


                //Fragment Shader
                fixed4 frag (v2f i) : SV_Target
                {
                    // 그냥 표면 파티클이 아니면 그리지 않는다
                    if(i.surfaceNormalLength < surfTrackThreshold) return fixed4(0, 0, 0, 0);


                    //프레그먼트의 월드 공간 좌표계에서 surface normal 을 구한다
                    float3 norVec = normalize(i.surfaceNormalWorld);


                    //뷰 벡터 = 해당 프레그먼트에서 카메라를 바라보는 벡터
                    //뷰 벡터를 월드 공간에서 구한다 (프레그먼트의 월드 공간 좌표를 넣어서 구할 수 있다)
                    float3 viewVec = normalize(UnityWorldSpaceViewDir(i.vertexWorld));


                    //빛 벡터 = 해당 프레그먼트에서 광원을 바라보는 벡터
                    //월드 공간에서 빛 벡터를 구한다
                    float3 lightVec = normalize(UnityWorldSpaceLightDir(i.vertexWorld));


                    /*
                        1. 일단 기본적인 난반사, Lambert Lighting

                        들어오는 빛의 양을 계산해서 그 만큼 자체 색을 가진다
                    */
                    float lightAmount = max(0, dot(norVec, lightVec));
                    float4 diffuseTerm = (lightAmount * _Color * _LightColor0);

                    diffuseTerm.w = 0.5f;
                    //diffuseTerm.w = max(0.1f, _diffuseAlpha - diffuseTerm.w);


                    
                    /*
                        2. 정반사, 스펙큘러

                        카메라에 들어오는 빛의 양만큼, 광원의 색이 들어온다
                    */
                    // 빛 반사 벡터
                    float3 reflectVec = reflect(lightVec, norVec);

                    // 눈에 들어오는 빛의 양
                    float lightAmountOnEye = max(0, dot(viewVec, reflectVec));

                    // 매끄러움 계산
                    float specular = pow(lightAmountOnEye, _Shininess);

                    // 정반사 빛
                    float4 specularTerm = specular * _SpecColor * _LightColor0;
                    
                    // 정반사는 금속 느낌이 나니까, 알파 값을 없애자
                    specularTerm.w = 0.5f;
                        
                        

                    float4 finalColor = diffuseTerm + specularTerm;


                    return finalColor;
            
                }
            ENDCG
        }
    }
}
