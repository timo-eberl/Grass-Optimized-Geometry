Shader "Unlit/GeometryGrass" {
    Properties {
        _Albedo1 ("Albedo 1", Color) = (1, 1, 1)
        _Albedo2 ("Albedo 2", Color) = (1, 1, 1)
        _AOColor ("Ambient Occlusion", Color) = (1, 1, 1)
        _TipColor ("Tip Color", Color) = (1, 1, 1)
        _Height("Grass Height", float) = 3
		_Width("Grass Width", range(0, 0.1)) = 0.05
        _FogColor ("Fog Color", Color) = (1, 1, 1)
        _FogDensity ("Fog Density", Range(0.0, 1.0)) = 0.0
        _FogOffset ("Fog Offset", Range(0.0, 10.0)) = 0.0
    }

    SubShader {
        Cull Off
        Zwrite On

        Tags {
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
        }

        Pass {
            CGPROGRAM
            #pragma vertex vp
            #pragma fragment fp
            #pragma geometry gp
            
            #pragma target 4.5

            #include "UnityPBSLighting.cginc"
            #include "AutoLight.cginc"
            #include "../Resources/Random.cginc"
            #include "../Resources/Simplex.compute"

            struct VertexData {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2g {
                float4 vertex : SV_POSITION;
            };

            struct g2f {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
                float4 worldPos : TEXCOORD1;
            };

            float4 _Albedo1, _Albedo2, _AOColor, _TipColor, _FogColor;
            float _FogDensity, _FogOffset;
            float _Height, _Width;

            v2g vp(VertexData v) {
                v2g o;
                o.vertex = v.vertex;
                
                return o;
            }

            float4 RotateAroundYInDegrees (float4 vertex, float degrees) {
                float alpha = degrees * UNITY_PI / 180.0;
                float sina, cosa;
                sincos(alpha, sina, cosa);
                float2x2 m = float2x2(cosa, -sina, sina, cosa);
                return float4(mul(m, vertex.xz), vertex.yw).xzyw;
            }

            float InvLerp(float a, float b, float v) {
                return (v-a) / (b-a);
            }

            [maxvertexcount(15)]
            void gp(point v2g points[1], inout TriangleStream<g2f> triStream) {
                uint i;
                float4 root = points[0].vertex;

                float4 clipspace = UnityObjectToClipPos(float4(root.xyz, 1));
                float3 weirdspace = clipspace.xyz;
                weirdspace /= -clipspace.w;
                weirdspace.x = weirdspace.x / 2.0f + 0.5f;
                weirdspace.y = weirdspace.y / 2.0f + 0.5f;
                weirdspace.z = -clipspace.w;
                const bool notClippedByNearClippingPlane = weirdspace.z >= -0.1f ? 0 : 1;
                const bool inFrustum = (weirdspace.x > -0.2f) && (weirdspace.x < 1.2f) && notClippedByNearClippingPlane;

                if (!inFrustum) return;
                
                float idHash = randValue(abs(root.x * 10000 + root.y * 100 + root.z * 0.05f + 2));
                idHash = randValue(idHash * 100000);

                const float3 worldPosition = mul((float3x3)unity_ObjectToWorld, root.xyz);
                const float cameraDistance = distance(_WorldSpaceCameraPos, worldPosition);
                const float lowLodChance = InvLerp(15, 25, cameraDistance);
                const uint lowLod = idHash < lowLodChance;
                
                const uint vertexCountMax = 15;
                const uint vertexCountLow = 9;
                const uint vertexCount = lowLod ? vertexCountLow : vertexCountMax;

                g2f v[vertexCountMax];
                
                for (i = 0; i < vertexCountMax; ++i) {
                    v[i].vertex = 0.0f;
                    v[i].uv = 0.0f;
                }
                
                float currentV = 0;
                float offsetV = 1.0f / (((vertexCount+1) / 2) - 1);
                
                float currentHeightOffset = 0;
                float currentVertexHeight = 0;
                
                for (i = 0; i < vertexCountMax; ++i) {
                
                    float widthMod = 1.0f - float(i) / float(vertexCount);
                    widthMod = pow(widthMod * widthMod, 1.0f / 3.0f);
                    
                    if (i % 2 == 0) {
                        v[i].vertex = float4(root.x - (_Width * widthMod), root.y + currentVertexHeight, root.z, 1);
                        v[i].uv = float2(0, currentV);
                    } else {
                        v[i].vertex = float4(root.x + (_Width * widthMod), root.y + currentVertexHeight, root.z, 1);
                        v[i].uv = float2(1, currentV);
                
                        currentV += offsetV;
                        currentVertexHeight = currentV * _Height * lerp(0.9f, 1.35f, idHash);
                    }
                
                    float sway = snoise(v[i].vertex.xyz * 0.35f + _Time.y * 0.25f) * v[i].uv.y * 0.07f;
                    v[i].vertex.xz += sway;
                    v[i].vertex.xyz -= root.xyz;
                    v[i].vertex = RotateAroundYInDegrees(v[i].vertex, idHash * 180.0f);
                    v[i].vertex.xyz += root.xyz;
                
                    v[i].worldPos = v[i].vertex;
                    v[i].vertex = UnityObjectToClipPos(v[i].vertex);
                
                }

                // for some reason this gives me error X4580 on my AMD GPU even though it should not (i think)
                // this error appears if i modify triStream in a loop of which the size is not compile-time constant
//                for (i = 0; i < vertexCount; ++i) {
//                    triStream.Append(v[i]);
//                }

                // so i do this funny workaround...

                for (i = 0; i < vertexCountLow; ++i) {
                    triStream.Append(v[i]);
                }

                if (lowLod) return;

                for (i = vertexCountLow; i < vertexCountMax; ++i) {
                    triStream.Append(v[i]);
                }
            }

            fixed4 fp(g2f i) : SV_Target {
                float4 col = lerp(_Albedo1, _Albedo2, i.uv.y);
                float3 lightDir = _WorldSpaceLightPos0.xyz;
                float ndotl = DotClamped(lightDir, normalize(float3(0, 1, 0)));

                float4 ao = lerp(_AOColor, 1.0f, i.uv.y);
                float4 tip = lerp(0.0f, _TipColor, i.uv.y * i.uv.y);
                
                float4 grassColor = (col + tip) * ndotl * ao;
 
                /* Fog */
                float viewDistance = length(_WorldSpaceCameraPos - i.worldPos);
                float fogFactor = (_FogDensity / sqrt(log(2))) * (max(0.0f, viewDistance - _FogOffset));
                fogFactor = exp2(-fogFactor * fogFactor);


                return lerp(_FogColor, grassColor, fogFactor);
            }

            ENDCG
        }
    }
}
