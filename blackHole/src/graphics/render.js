import * as THREE from 'three';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass';
import { ShaderPass } from 'three/examples/jsm/postprocessing/ShaderPass';
import { CopyShader } from 'three/examples/jsm/shaders/CopyShader';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass';
import { CameraDragControls } from "../camera/CameraDragControls";
import { Observer } from "../camera/Observer";
import { Vector2 } from 'three/src/math/Vector2';
import fragmentShader from './fragmentShader.glsl?raw';

// 真的不想写了,傻逼设计
export function createRenderer() {
  const renderer = new THREE.WebGLRenderer()
  renderer.setClearColor(0x000000, 1.0)
  renderer.setSize(window.innerWidth, window.innerHeight) // res
  renderer.autoClear = false
  return renderer;
}

export function createScene(renderer) {
  // scene and camera
  const scene = new THREE.Scene()
  const camera = new THREE.Camera()
  camera.position.z = 1

  const composer = new EffectComposer(renderer);
  const renderPass = new RenderPass(scene, camera)
  const bloomPass = new UnrealBloomPass(new Vector2(128, 128), 0.8, 2.0, 0.0)
  const shaderPass = new ShaderPass(CopyShader);
  shaderPass.renderToScreen = true;
  composer.addPass(renderPass);
  composer.addPass(bloomPass);
  composer.addPass(shaderPass);

  return {
    scene, composer, bloomPass
  }
}

export function createCamera(renderer) {
  const observer = new Observer(60.0, window.innerWidth / window.innerHeight, 1, 80000)
  const cameraControl = new CameraDragControls(observer, renderer.domElement) 
  return {
    observer, cameraControl
  }
}

export function loadTextures() {
  const textures = new Map();
  const textureLoader = new THREE.TextureLoader()
  const loadTexture = (name, image, interpolation, wrap = THREE.ClampToEdgeWrapping) => {
    textures.set(name, null);
    textureLoader.load(image, (texture) => {
      texture.magFilter = interpolation
      texture.minFilter = interpolation
      texture.wrapT = wrap
      texture.wrapS = wrap
      textures.set(name, texture);
    })
  }

  loadTexture('bg1', 'https://cdn.glitch.com/631097e7-5a58-45aa-a51f-cc6b44f8b30b%2Fmilkyway.jpg?1545745139132', THREE.NearestFilter)
  loadTexture('star', 'https://cdn.glitch.com/631097e7-5a58-45aa-a51f-cc6b44f8b30b%2Fstars.png?1545722529872', THREE.LinearFilter)
  loadTexture('disk', 'https://cdn.glitch.com/631097e7-5a58-45aa-a51f-cc6b44f8b30b%2FdQ.png?1545846159297', THREE.LinearFilter)

  window.onbeforeunload = () => {
    for (const texture of textures.values()) {
      texture.dispose();
    }
  }

  return textures;
}

export async function createShaderProjectionPlane(uniforms) {

  const vertexShader = document.getElementById('vertexShader')?.textContent
  if (!vertexShader) {
    throw new Error('Error reading vertex shader!');
  }
  // 函数获取到一个着色器预处理指令,包含一些定义常量（Defined Constant）的字符串
  // 这个着色器预处理指令可以作为 fragmentShader 字符串的前缀，
  // 在编译时对 fragmentShader 字符串进行预处理，以便在着色器程序中使用预定义的常量
  const defines = getShaderDefineConstant('medium');
  // threejs的自定义shader程序
  const material = new THREE.ShaderMaterial({
    uniforms: uniforms,
    vertexShader,
    fragmentShader: defines + fragmentShader,
  })
  material.needsUpdate = true;

  const mesh = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), material)


  async function changePerformanceQuality(quality) {
    const defines = getShaderDefineConstant(quality);
    material.fragmentShader = defines + fragmentShader;
    material.needsUpdate = true;
  }


  function getShaderDefineConstant(quality) {
    let STEP, NSTEPS;
    switch (quality) {
      case 'low':
        STEP = 0.1;
        NSTEPS = 300;
        break;
      case 'medium':
        STEP = 0.05;
        NSTEPS = 600;
        break;
      case 'high':
        STEP = 0.02;
        NSTEPS = 1000;
        break;
      default:
        STEP = 0.05;
        NSTEPS = 600;
    }
    return `
  #define STEP ${STEP} 
  #define NSTEPS ${NSTEPS} 
`
  }

  return {
    mesh,
    changePerformanceQuality
  };
}
