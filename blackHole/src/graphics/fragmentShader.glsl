//#define STEP 0.04
//#define NSTEPS 700
#define PI 3.141592653589793238462643383279
#define DEG_TO_RAD (PI/180.0)
#define ROT_Y(a) mat3(1, 0, 0, 0, cos(a), sin(a), 0, -sin(a), cos(a))
#define ROT_Z(a) mat3(cos(a), -sin(a), 0, sin(a), cos(a), 0, 0, 0, 1)


uniform float time;
uniform vec2 resolution;

uniform vec3 cam_pos;
uniform vec3 cam_dir;
uniform vec3 cam_up;
uniform float fov;
uniform vec3 cam_vel;

const float MIN_TEMPERATURE = 1000.0;
const float TEMPERATURE_RANGE = 39000.0;

uniform bool accretion_disk;
// 是否开启纹理
uniform bool use_disk_texture;
const float DISK_IN = 2.0;
const float DISK_WIDTH = 4.0;
// 多普勒效应
uniform bool doppler_shift;
// 洛伦兹变换 是相对论物理学中的一个基本概念，用于描述在不同参考系之间测量出的物理量的关系
uniform bool lorentz_transform;
// 束流效应
uniform bool beaming;

uniform sampler2D bg_texture;
uniform sampler2D star_texture;
// 纹理采集
uniform sampler2D disk_texture;
// 2D 矢量映射到 [-1,1] 的正方形框架中
vec2 square_frame(vec2 screen_size){
  vec2 position = 2.0 * (gl_FragCoord.xy / screen_size.xy) - 1.0; 
  return position;
}
// 将笛卡尔坐标系中的 3D 矢量转换为球面坐标系中的 2D 矢量
vec2 to_spherical(vec3 cartesian_coord){
  vec2 uv = vec2(atan(cartesian_coord.z,cartesian_coord.x), asin(cartesian_coord.y)); 
  uv *= vec2(1.0/(2.0*PI), 1.0/PI); //long, lat
  uv += 0.5;
  return uv;
}

//  u 物体速度，而 v 是观察者的速度
// 洛伦兹效应:当两个物体相对运动时，它们之间的距离、时间和速度等物理量会发生变化
vec3 lorentz_transform_velocity(vec3 u, vec3 v){ 
  // 使用 length() 函数计算观察者速度向量 v 的模长，并检查其是否大于零。如果速度向量的模长为零，则不需要进行任何转换，直接返回原始速度向量 u
  float speed = length(v);
  if (speed > 0.0){
    // 点积运算符 dot() 和开方函数 sqrt() 计算出相对论因子 gamma，用于描述速度相对论效应下的收缩和时间延迟等效应
    float gamma = 1.0/sqrt(1.0-dot(v,v));
    // 分母项 denominator，用于后续的速度向量更新。这个分母项是一个标量值，表示两个参考系之间的速度差异
    float denominator = 1.0 - dot(v,u);

    // 一系列复杂的相对论运算...无需关注其推导,直接调用,终值是返回一个新的速度向量 new_u
    vec3 new_u = (u/gamma - v + (gamma/(gamma+1.0)) * dot(u,v)*v)/denominator;
    return new_u;
  }
  return u;
}
// 将给定的色温（单位为开尔文）转换为相应的RGB值
vec3 temp_to_color(float temp_kelvin){
  vec3 color;
  // 1k ~ 40k rescale by dividing 100
  temp_kelvin = clamp(temp_kelvin, 1000.0, 40000.0) / 100.0;
  if (temp_kelvin <= 66.0){
    color.r = 255.0;
    color.g = temp_kelvin;
    color.g = 99.4708025861 * log(color.g) - 161.1195681661;
    if (color.g < 0.0) color.g = 0.0;
    if (color.g > 255.0)  color.g = 255.0;
  } else {
    color.r = temp_kelvin - 60.0;
    if (color.r < 0.0) color.r = 0.0;
    color.r = 329.698727446 * pow(color.r, -0.1332047592);
    if (color.r < 0.0) color.r = 0.0;
    if (color.g > 255.0) color.r = 255.0;
    color.g = temp_kelvin - 60.0;
    if (color.g < 0.0) color.g = 0.0;
    color.g = 288.1221695283 * pow(color.g, -0.0755148492);
    if (color.g > 255.0)  color.g = 255.0;  
  }
  if (temp_kelvin >= 66.0){
    color.b = 255.0;
  } else if (temp_kelvin <= 19.0){
    color.b = 0.0;
  } else {
    color.b = temp_kelvin - 10.0;
    color.b = 138.5177312231 * log(color.b) - 305.0447927307;
    if (color.b < 0.0) color.b = 0.0;
    if (color.b > 255.0) color.b = 255.0;
  }
  color /= 255.0; // make it 0..1
  return color;
}

void main()	{
 
// 用于从相机位置发射光线，生成追踪光线的方向向量

// 根据相机的视场角（fov）计算出屏幕上一个像素的大小，即 uvfov。
// 因为 Three.js 中的视场角是以度为单位的，所以需要将其转换为弧度，乘以 DEG_TO_RAD 常量进行转换。
  float uvfov = tan(fov / 2.0 * DEG_TO_RAD);
  // uv表示当前像素在屏幕上的位置，它通过调用 square_frame(resolution) 函数获取得到。
  // 这个函数返回了一个位于屏幕中心的正方形区域，其边长为屏幕高度的一半，用于规范化像素坐标。
  vec2 uv = square_frame(resolution); 

  uv *= vec2(resolution.x/resolution.y, 1.0);
  vec3 forward = normalize(cam_dir); // 
  vec3 up = normalize(cam_up);
  vec3 nright = normalize(cross(forward, up));
  up = cross(nright, forward);
  // 根据像素坐标和相机位置、方向向量计算出该像素对应的光线的起点 pixel_pos
  vec3 pixel_pos =cam_pos + forward +
                 nright*uv.x*uvfov+ up*uv.y*uvfov;
  
  // 光线的方向向量 ray_dir 
  vec3 ray_dir = normalize(pixel_pos - cam_pos); // 
  
  



  // light aberration alters ray path 
  if (lorentz_transform)
    ray_dir = lorentz_transform_velocity(ray_dir, cam_vel);
  // initial color
  vec4 color = vec4(0.0,0.0,0.0,1.0);

  // geodesic by leapfrog integration

  vec3 point = cam_pos;
  vec3 velocity = ray_dir;
  vec3 c = cross(point,velocity);
  float h2 = dot(c,c);

  
  // 伽马因子 ray_gamma 的值，其中 cam_vel 是观察者（相机）的速度向量。
  // 点积运算符 dot() 计算了观察者速度 cam_vel 和自身的内积，
  // 然后将这个值带入到基本相对论公式 ray_gamma = 1.0/sqrt(1.0-v*v/c*c) 中进行计算
  // 得到伽马因子 ray_gamma。在这里，由于 cam_vel 表示的是观察者相对于场景的速度，因此需要使用负号
  float ray_gamma = 1.0/sqrt(1.0-dot(cam_vel,cam_vel));

  // 计算射线多普勒因子的值，其中 ray_gamma 是由相对论效应引起的伽马因子，而 -cam_vel 则是观察者（相机）的速度向量
  float ray_doppler_factor = ray_gamma * (1.0 + dot(ray_dir, -cam_vel));
    
  float ray_intensity = 1.0;
  // 开启束流效应
  // 使用一个布尔值来控制,加入了辐射束缩放效应
  if (beaming)
  // 将多普勒因子 disk_doppler_factor 的三次方作为指数
    // 对吸积盘的降低亮度效应
    // 速度越快时，束缩放效应就越强，因为多普勒因子会更接近于 1
    // pow() 函数是一个数学函数，用于计算一个数的幂。
    ray_intensity /= pow(ray_doppler_factor , 3.0);
  
  
  vec3 oldpoint; 
  float pointsqr;
  
  float distance = length(point);

  // 光线追踪算法
  for (int i=0; i<NSTEPS;i++){ 
    // 定义了一个变量 oldpoint 来保存上一个点的位置，并在每次迭代中更新该值。这个变量将用于判断光线是否与事件视界相交

// 核心算法:计算光线在空间中的运动轨迹,并计算到当前坐标系原点的距离
// 欧拉法数值积分方法和测地线方程来计算下一个时间步长中的位置和速度，并更新上一个点的位置信息。

// 将当前位置 point 赋值给变量 oldpoint，以便在判断光线是否与事件视界相交时使用,step是步长,velocity是速度向量
    oldpoint = point; 
    point += velocity * STEP;
    vec3 accel = -1.5 * h2 * point / pow(dot(point,point),2.5);
    // 得到位置
    velocity += accel * STEP;    
    // 取模
    distance = length(point);


    // 计算当前位置到原点的距离 distance，如果小于 0.0，则跳出循环。
    if ( distance < 0.0) break;
    
    bool horizon_mask = distance < 1.0 && length(oldpoint) > 1.0;
    //光线被黑洞捕获啦,设置颜色变黑色,并退出循环
    if (horizon_mask) {
      vec4 black = vec4(0.0,0.0,0.0,1.0);
      color += black;
      break;
    }
    // 用于计算黑洞周围吸积盘的亮度和颜色
    if (accretion_disk){
      // oldpoint.y * point.y < 0.0，则说明光线从上方或下方穿过吸积盘，并需要进一步计算吸积盘的属性。
      if (oldpoint.y * point.y < 0.0){
        float lambda = - oldpoint.y/velocity.y;
        vec3 intersection = oldpoint + lambda*velocity;
        float r = length(intersection);//dot(intersection,intersection);
        if (DISK_IN <= r&&r <= DISK_IN+DISK_WIDTH ){
          float phi = atan(intersection.x, intersection.z);
          
          vec3 disk_velocity = vec3(-intersection.x, 0.0, intersection.z)/sqrt(2.0*(r-1.0))/(r*r); 
          phi -= time;//length(r);
          phi = mod(phi , PI*2.0);
          float disk_gamma = 1.0/sqrt(1.0-dot(disk_velocity, disk_velocity));
          // 计算了伽马因子 disk_gamma 和多普勒因子 disk_doppler_factor，以考虑相对论效应的影响
          float disk_doppler_factor = disk_gamma*(1.0+dot(ray_dir/distance, disk_velocity));
          
          if (use_disk_texture){
          // 开启纹理,否则则使用光线追踪去计算像素点的颜色
            vec2 tex_coord = vec2(mod(phi,2.0*PI)/(2.0*PI),1.0-(r-DISK_IN)/(DISK_WIDTH)); //当前像素所对应的纹理坐标
            // 纹理图像中获取对应的颜色值，并将其除以光线和吸积盘之间的多普勒因子的平方。得到的颜色值为四维向量 disk_color
            vec4 disk_color = texture2D(disk_texture, tex_coord) / (ray_doppler_factor * disk_doppler_factor);
            // 计算透明度,根据 disk_alpha。使用 dot() 函数计算颜色与自身的内积，然后除以一个常数 4.5，最后使用 clamp() 函数将其映射到 [0.0, 1.0] 范围内。
            float disk_alpha = clamp(dot(disk_color,disk_color)/4.5,0.0,1.0);

            if (beaming)
              disk_alpha /= pow(disk_doppler_factor,3.0);
            
            color += vec4(disk_color)*disk_alpha;
          } else {
          
        //  计算了吸积盘的颜色,或使用纹理贴图
        //  另一种是使用黑体辐射定律。
          float disk_temperature = 10000.0*(pow(r/DISK_IN, -3.0/4.0));

          // 计算吸积盘的温度    // 如果为 true，则需要考虑多普勒频移
          if (doppler_shift)
          // ray_doppler_factor 是相对光源的多普勒因子，disk_doppler_factor 则是相对吸积盘的多普勒因子。
            disk_temperature /= ray_doppler_factor*disk_doppler_factor;//代表了光线和吸积盘之间的多普勒频移因子，它可以影响吸积盘的颜色和亮度
          // 计算得到的吸积盘温度转化为颜色值 这里为了简便使用黑体辐射算法
          vec3 disk_color = temp_to_color(disk_temperature);
          float disk_alpha = clamp(dot(disk_color,disk_color)/3.0,0.0,1.0);//使用 dot() 函数计算 disk_color 和自身的内积，然后除以
                                                                            // 3.0 得到平均亮度值，并使用 clamp() 函数将其映射在 [0.0, 1.0] 范围内
          if (beaming)
          // 用 pow() 函数将 disk_doppler_factor 的三次方作为指数，对 disk_alpha 进行额外的缩放处理
            disk_alpha /= pow(disk_doppler_factor,3.0);
            // 最终渲染可以组合转化后的色温值和透明度,维护一个四维向量rgba并添加到color中
          color += vec4(disk_color, 1.0)*disk_alpha;
          
          }
        }
      }
    }
    
  }
  
  // 在光线穿过黑洞事件视界之后，对背景星空进行渲染,噪声云雾模拟效果
  if (distance > 1.0){
    ray_dir = normalize(point - oldpoint);
    vec2 tex_coord = to_spherical(ray_dir * ROT_Z(45.0 * DEG_TO_RAD));
    vec4 star_color = texture2D(star_texture, tex_coord);
    if (star_color.g > 0.0){
      float star_temperature = (MIN_TEMPERATURE + TEMPERATURE_RANGE*star_color.r);
      // arbitrarily sets background stars' velocity for random shifts
      float star_velocity = star_color.b - 0.5;
      float star_doppler_factor = sqrt((1.0+star_velocity)/(1.0-star_velocity));
      if (doppler_shift)
        star_temperature /= ray_doppler_factor*star_doppler_factor;
      
      color += vec4(temp_to_color(star_temperature),1.0)* star_color.g;
    }

    color += texture2D(bg_texture, tex_coord) * 0.25;
  }
  gl_FragColor = color*ray_intensity;
}