
import * as THREE from 'three';

export class Observer extends THREE.PerspectiveCamera {
  constructor(fov, ratio, near, far) {
    super(fov, ratio, near, far)
    this.time = 0
    this.theta = 0
    this.angularVelocity = 0
    this.maxAngularVelocity = 0
    this.velocity = new THREE.Vector3()

    this.position.set(0, 0, 1)
    this.direction = new THREE.Vector3();

    this.moving = false
    this.timeDilation = false
    this.incline = -5 * Math.PI / 180
  }

  set distance(r) {
    this.r = r
    // w
    this.maxAngularVelocity = 1 / Math.sqrt(2.0 * (r - 1.0)) / this.r
    // p
    this.position.normalize().multiplyScalar(r)
  }

  get distance() {
    return this.r
  }

  setDirection(pitch, yaw) {
    let originalDirection = new THREE.Vector3(0, 0, -1)
    let rotation = new THREE.Euler(0, 0, 0, 'YXZ')
    rotation.set(pitch, yaw, 0)

    let newDirection = new THREE.Vector3()
    newDirection.copy(originalDirection).applyEuler(rotation)

    this.direction = newDirection.normalize();
  }

  update(delta) {
    if (this.timeDilation) {
      this.delta = Math.sqrt((delta * delta * (1.0 - this.angularVelocity * this.angularVelocity)) / (1 - 1.0 / this.r));
    } else {
      this.delta = delta
    }

    this.theta += this.angularVelocity * this.delta
    let cos = Math.cos(this.theta)
    let sin = Math.sin(this.theta)


    this.position.set(this.r * sin, 0, this.r * cos)
    // change direction of movement
    this.velocity.set(cos * this.angularVelocity, 0, -sin * this.angularVelocity)

    let inclineMatrix = (new THREE.Matrix4()).makeRotationX(this.incline)
    this.position.applyMatrix4(inclineMatrix)
    this.velocity.applyMatrix4(inclineMatrix)

    if (this.moving) {
      if (this.angularVelocity < this.maxAngularVelocity)
        this.angularVelocity += this.delta / this.r
      else
        this.angularVelocity = this.maxAngularVelocity

    } else {
      if (this.angularVelocity > 0.0)
        this.angularVelocity -= this.delta / this.r
      else {
        this.angularVelocity = 0
        this.velocity.set(0.0, 0.0, 0.0)
      }
    }

    this.time += this.delta
  }

}