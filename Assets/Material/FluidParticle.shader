Shader "Fluid/FluidParticle"
{
    Properties
    {
        // 자체적으로 가지는 색깔
        _Color ( "Color", Color) = (0,0,1,1)

        // 간접광, ambient
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

                    // 기본 정보
                    float4 vertex : POSITION;

                    // 모델의 노말 벡터를 사용하지 않고
                    // 계산한 surface normal 을 이용해서 라이팅 계산을 해야 한다
                    // float3 normal : NORMAL;
                };



                struct v2f
                {
                    
                    // 각 공간에서 프레그먼트에 해당하는 정점의 위치
                    float4 vertexClip : SV_POSITION;
                    float4 vertexWorld : TEXCOORD1;
                    

                    // 커스텀
                    // 월드공간에서 구한, 물 표면 노멀벡터 -> 공기에서 물을 향한다
                    float3 surfaceNormalWorld : TEXCOORD2;

                    // 노멀 벡터의 크기
                    float surfaceNormalLength : SNL;

                };

                



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




                // 그리려는 모델의 반지름
                float particleRadius;


                // 표면과 내부를 구분하는 threshold
                float surfTrackThreshold;


                // fluid 의 영역
                float3 limitRange;



                // 공을 이루는 각 정점마다 이 정점 셰이더가 적용된다
                v2f vert (appdata v, uint instanceID : SV_InstanceID)
                {
                    v2f o;

                    // 모델의 이동 위치를 구한다
                    float3 pos = particles[instanceID].position;


                    // position 값을 가져와서, 정점에 이동변환으로 적용시켜야 한다
                    // 이동변환 + 확대변환
                    float4x4 affinMat = float4x4 (
                                                    particleRadius, 0, 0, pos.x,
                                                    0, particleRadius, 0, pos.y,
                                                    0, 0, particleRadius, pos.z,
                                                    0,0,0,1
                                                );


                    // 모델의 정점에 이동변환을 적용한다
                    v.vertex = mul(affinMat, v.vertex);


                    // 정점의 위치가 변했으니, 노멀벡터도 변환을 해주어야 한다
                    // 이동변환 외에, 균등 확대만 적용됐으므로 이를 노멀에 그대로 적용할 수 있다

                    float3x3 L = float3x3( 
                                            particleRadius, 0, 0,
                                            0, particleRadius, 0,
                                            0, 0, particleRadius
                                        );

                    float3 normalWorld = mul( L, particles[instanceID].surfNormal);



                    // v2f o 대입
                    o.vertexWorld = v.vertex;
                    o.vertexClip = UnityWorldToClipPos(v.vertex);
                    
                    o.surfaceNormalWorld = normalWorld;

                    o.surfaceNormalLength = length(normalWorld);


                    return o;
                }

                
                
                


                
                fixed4 frag (v2f i) : SV_Target
                {

                    // 그냥 표면 파티클이 아니면 그리지 않는다
                    if(i.surfaceNormalLength < surfTrackThreshold) return fixed4(0, 0, 0, 0);



                    // 프레그먼트의 surface normal 을 구한다
                    // 이게 일단 fluid 를 향하는 방향이라고 생각한다 => 반대 방향으로 해서 액체 표면 바깥을 향하게하자
                    float3 norVec = normalize(-i.surfaceNormalWorld);



                    // 뷰 벡터 = 해당 프레그먼트에서 카메라를 바라보는 벡터
                    // 뷰 벡터를 월드 공간에서 구한다 (프레그먼트의 월드 공간 좌표를 넣어서 구할 수 있다)
                    float3 veiwVec = normalize(UnityWorldSpaceViewDir(i.vertexWorld));



                    // 빛 벡터 = 해당 프레그먼트에서 광원을 바라보는 벡터
                    // 월드 공간에서 빛 벡터를 구한다
                    float3 lightVec = normalize(UnityWorldSpaceLightDir(i.vertexWorld));




                    // 1. 일단 기본적으로 Lambert, 난반사에 의한 라이팅은 계산을 한다

                    // 들어오는 빛의 양
                    // 표면에 있을수록 노멀벡터가 크기가 커서, 표면에 있으면 자동으로 lightAmount 가 크다
                    // 그래서 자동으로 밑으로 표면에서 멀어질수록 색이 어두워진다
                    float lightAmount = max(_Ambient, dot(norVec, lightVec));


                    // 들어오는 빛의 양만큼 빛난다
                    // 근데 _Ambient 가 투명도에 영향을 주면 안된다고 생각해
                    float4 diffuseTerm;

                    diffuseTerm = (lightAmount * _Color * _LightColor0);
                    diffuseTerm.w = max(0.1f, _diffuseAlpha - diffuseTerm.w);


                    // 2. 정반사, 스펙큘러

                    // 빛 반사 벡터
                    float3 reflectVec = reflect(lightVec, norVec);

                    // 눈에 들어오는 빛의 양
                    float lightAmountOnEye = max(_Ambient, dot(veiwVec, reflectVec));

                    // 매끄러움 계산
                    float specular = pow(lightAmountOnEye, _Shininess);

                    // 정반사 빛
                    float4 specularTerm = specular * _SpecColor * _LightColor0;
                    
                    // 정반사는 금속 느낌이 나니까, 알파 값을 없애자
                    specularTerm.w = 0; 
                        
                        

                    float4 finalColor = diffuseTerm + specularTerm;


                    return finalColor;
            
                }
            ENDCG
        }
    }
}
